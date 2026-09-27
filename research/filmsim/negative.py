"""Render scene light through a colour negative and a print, for looks with no official LUT.

Scene linear RGB (BT.2020 = F-Gamut, the pipeline's working space)
  -> exposure of each emulsion layer, from the datasheet's spectral sensitivities
  -> negative density, from the datasheet's characteristic curves
  -> positive, by a print curve whose contrast and saturation are set by eye

The datasheet covers the first two steps. How a negative is printed or scanned is not on
it, so `PrintSettings` holds those choices; they were tuned against reference scans.
The positive is taken as display-linear sRGB, so the film's own primaries carry through.
"""

from __future__ import annotations

from dataclasses import dataclass
from types import ModuleType

import colour
import numpy as np

from .cube import CubeLUT
from .flog2 import FLOG2
from .gamut import BT2020, RGBSpace

# Layer order matches the output channels: the cyan-forming layer controls red, and so on.
LAYERS = ("cyan_forming", "magenta_forming", "yellow_forming")
MIDDLE_GREY = 0.18


def _sensitivity(film: ModuleType, layer: str, wavelengths: np.ndarray) -> np.ndarray:
    """Relative sensitivity (linear) on `wavelengths`, zero where the sheet draws no curve."""
    table = film.LOG_SENSITIVITY[layer]
    wl = np.array(sorted(table))
    log_s = np.array([table[w] for w in wl])
    s = np.interp(wavelengths, wl, 10.0 ** log_s, left=0.0, right=0.0)
    return s


def layer_matrix(film: ModuleType, space: RGBSpace = BT2020) -> np.ndarray:
    """3x3 from linear `space` RGB to layer exposure (cyan-, magenta-, yellow-forming).

    Fitted by least squares over the 24 ColorChecker reflectances under D65: their RGB on
    one side, their exposure of each layer (reflectance x D65 x sensitivity) on the other.
    Rows are scaled so a neutral gives the same exposure in every layer, as a daylight
    film is balanced to.
    """
    shape = colour.SpectralShape(400, 700, 10)
    wl = shape.wavelengths
    d65 = colour.SDS_ILLUMINANTS["D65"].copy().align(shape).values
    patches = colour.SDS_COLOURCHECKERS["ColorChecker N Ohta"]
    cmfs = colour.MSDS_CMFS["CIE 1931 2 Degree Standard Observer"].copy().align(shape)

    illuminant = colour.SDS_ILLUMINANTS["D65"].copy().align(shape)
    aligned = [sd.copy().align(shape) for sd in patches.values()]
    refl = np.array([sd.values for sd in aligned])
    xyz = np.array([colour.sd_to_XYZ(sd, cmfs=cmfs, illuminant=illuminant) for sd in aligned]) / 100.0
    rgb = xyz @ space.from_xyz().T
    sens = np.stack([_sensitivity(film, layer, wl) for layer in LAYERS])
    exposure = (refl * d65) @ sens.T

    m, *_ = np.linalg.lstsq(rgb, exposure, rcond=None)
    m = m.T
    return m / (m @ np.ones(3))[:, None]


def negative_density(film: ModuleType, log_h: np.ndarray) -> np.ndarray:
    """Status M density (R, G, B) for per-layer log10 exposure (..., 3).

    Beyond the drawn range the curves continue straight with their end slopes: the toe is
    nearly flat already, and a negative keeps recording well past the sheet's top.
    """
    x = np.asarray(film.LOG_EXPOSURE_LUX_SECONDS)
    out = np.empty(np.shape(log_h))
    for c, key in enumerate("RGB"):
        d = np.asarray(film.STATUS_M[key])
        h = log_h[..., c]
        lo, hi = (d[1] - d[0]) / (x[1] - x[0]), (d[-1] - d[-2]) / (x[-1] - x[-2])
        v = np.interp(h, x, d)
        v = np.where(h < x[0], d[0] + (h - x[0]) * lo, v)
        out[..., c] = np.where(h > x[-1], d[-1] + (h - x[-1]) * hi, v)
    return out


def straight_line_gamma(film: ModuleType) -> np.ndarray:
    """Slope of each characteristic curve over two stops either side of the reference exposure."""
    x = np.asarray(film.LOG_EXPOSURE_LUX_SECONDS)
    near = np.abs(x - film.LOG_H_REF) <= 0.6
    return np.array([np.polyfit(x[near], np.asarray(film.STATUS_M[k])[near], 1)[0] for k in "RGB"])


@dataclass(frozen=True)
class PrintSettings:
    """How the negative is turned into a positive. Not on the datasheet; set by eye."""

    contrast: float = 1.35       # print gamma on top of the negative, in log units
    saturation: float = 1.0      # spread of the channels around their mean, in log units
    black: float = 0.012         # display-linear floor: paper D-max or a scanner's black point
    white: float = 1.0           # display-linear ceiling of the print curve


# Tuned against reference scans of Portra 400VC (sky, red balloons, green upholstery,
# skin, a red gingham cloth). On the ColorChecker this gives about 1.2x the chroma of the
# true colours, reds 1 to 4° towards orange, greens 5° towards yellow, and blue sky on hue.
# Neutrals stay neutral.
PORTRA_400VC = PrintSettings(contrast=1.5, saturation=1.7)


def render(linear: np.ndarray, film: ModuleType, settings: PrintSettings, m: np.ndarray | None = None) -> np.ndarray:
    """Scene-linear BT.2020 (..., 3) to sRGB code values in [0, 1]."""
    if m is None:
        m = layer_matrix(film)
    exposure = np.clip(np.asarray(linear, dtype=np.float64) @ m.T, 1e-6, None)
    log_h = np.log10(exposure / MIDDLE_GREY) + film.LOG_H_REF
    density = negative_density(film, log_h)
    ref = negative_density(film, np.full(3, film.LOG_H_REF))

    # Density above mid-grey, divided by each layer's gamma: back to scene log units, with the
    # toe and shoulder of each curve kept. Dividing out the gammas balances the orange mask
    # and B's steeper curve, as printing filtration does.
    x = (density - ref) / straight_line_gamma(film)
    mean = x.mean(axis=-1, keepdims=True)
    x = mean + settings.saturation * (x - mean)

    # Print curve: a smooth S in log exposure that keeps mid-grey at 18%.
    e = MIDDLE_GREY * 10.0 ** x
    c = settings.contrast
    k = MIDDLE_GREY ** c * (1 / MIDDLE_GREY - 1)
    y = e ** c / (e ** c + k)
    y = settings.black + (settings.white - settings.black) * y
    return colour.cctf_encoding(np.clip(y, 0.0, 1.0), function="sRGB")


def bake_lut(film: ModuleType, settings: PrintSettings, size: int = 33, title: str = "") -> CubeLUT:
    """F-Log2 / F-Gamut codes in, sRGB codes out: the same interface as the official LUTs."""
    m = layer_matrix(film)
    grid = CubeLUT.identity(size).table
    linear = FLOG2.decode(grid)
    return CubeLUT(size, render(linear, film, settings, m), np.zeros(3), np.ones(3), title)
