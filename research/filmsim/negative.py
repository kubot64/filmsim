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

from .anchor import MIDDLE_GREY
from .cube import CubeLUT
from .flog2 import FLOG2
from .gamut import BT2020, BT709_LUMA, RGBSpace

# Layer order matches the output channels: the cyan-forming layer controls red, and so on.
LAYERS = ("cyan_forming", "magenta_forming", "yellow_forming")


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
    illuminant = colour.SDS_ILLUMINANTS["D65"].copy().align(shape)
    d65 = illuminant.values
    patches = colour.SDS_COLOURCHECKERS["ColorChecker N Ohta"]
    cmfs = colour.MSDS_CMFS["CIE 1931 2 Degree Standard Observer"].copy().align(shape)

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


IDENTITY3 = ((1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0))


@dataclass(frozen=True)
class PrintSettings:
    """How the negative is turned into a positive. Not on the datasheet; fitted to a real scan."""

    contrast: float = 1.35       # print gamma on top of the negative, in log units
    saturation: float = 1.0      # spread of the channels around their luminance, in log units
    shadow_stops: float = 7.0    # how far below mid-grey the film base (D-min) prints as black
    black: float = 0.012         # display-linear floor: paper D-max or a scanner's black point
    white: float = 1.0           # display-linear ceiling of the print curve
    # The scanner's colour matrix on display-linear RGB. Rows sum to 1, so greys stay grey.
    scan_matrix: tuple[tuple[float, float, float], ...] = IDENTITY3


# Fitted to a scan of Portra 400VC with an X-Rite ColorChecker in the frame (`portra400vc_scan`):
# contrast, saturation, shadows, black and the scanner matrix, by Powell on the mean ΔE2000 of
# the 24 patches, with the scan's grey balance and brightness left free. Mean ΔE 3.3, median
# 2.8 (the true ColorChecker colours are 17 from the scan). The matrix is what moves reds
# towards orange (the scan's red is at 36°; without it the model put red at 18°) and blues
# towards cyan, as the user's reference scans also showed.
PORTRA_400VC = PrintSettings(
    contrast=1.83,
    saturation=1.15,
    shadow_stops=9.67,
    black=0.0,
    scan_matrix=((1.267, -0.317, 0.050), (0.033, 0.905, 0.062), (-0.050, 0.114, 0.936)),
)


def tone(film: ModuleType, log_h: np.ndarray) -> np.ndarray:
    """Log exposure to scene log units through the film's tone, the same curve for every channel.

    The curve is the mean of the three characteristic curves, each over its own gamma: the toe
    that compresses the shadows and the shoulder stay, while the orange mask and B's steeper
    curve drop out, as a scanner's per-channel levels do. Giving each channel its own curve
    tinted neutrals: the three toes start at different exposures, and the ColorChecker's
    black came out purple.
    """
    log_h = np.asarray(log_h, dtype=np.float64)
    gamma = straight_line_gamma(film)
    ref = negative_density(film, np.full(3, film.LOG_H_REF))
    per_channel = (negative_density(film, np.stack([log_h] * 3, axis=-1)) - ref) / gamma
    return per_channel.mean(axis=-1)


def render(linear: np.ndarray, film: ModuleType, settings: PrintSettings, m: np.ndarray | None = None) -> np.ndarray:
    """Scene-linear BT.2020 (..., 3) to sRGB code values in [0, 1]."""
    if m is None:
        m = layer_matrix(film)
    exposure = np.clip(np.asarray(linear, dtype=np.float64) @ m.T, 1e-6, None)
    log_h = np.log10(exposure / MIDDLE_GREY) + film.LOG_H_REF
    x = tone(film, log_h)

    # Split into luminance and the channels' offsets from it, in log units. Saturation scales
    # the offsets, so a saturated colour gets deeper rather than brighter (spreading around
    # the plain mean lifted greens by 8 L*). Below mid-grey the luminance is stretched so the
    # film base (D-min) prints `shadow_stops` down, where a scanner puts its black point;
    # stretching the offsets too doubled the chroma of dark skin.
    luma = x @ np.asarray(BT709_LUMA)
    film_base = float(tone(film, -10.0))
    stretch = settings.shadow_stops * np.log10(2) / -film_base
    stretched = np.where(luma < 0, luma * stretch, luma)
    x = stretched[..., None] + settings.saturation * (x - luma[..., None])

    # Print curve: a smooth S in log exposure that keeps mid-grey at 18%.
    e = MIDDLE_GREY * 10.0 ** x
    c = settings.contrast
    k = MIDDLE_GREY ** c * (1 / MIDDLE_GREY - 1)
    y = e ** c / (e ** c + k)
    y = settings.black + (settings.white - settings.black) * y
    y = y @ np.asarray(settings.scan_matrix).T
    return colour.cctf_encoding(np.clip(y, 0.0, 1.0), function="sRGB")


def bake_lut(film: ModuleType, settings: PrintSettings, size: int = 65, title: str = "") -> CubeLUT:
    """F-Log2 / F-Gamut codes in, sRGB codes out: the same interface as the official LUTs.

    65 like the official LUTs. At 33 the trilinear lookup put mid-grey at 0.166 / 0.172 / 0.171
    instead of 0.18 (a faint cyan) and grey ramps were up to ΔE 1.7 off the model; at 65 greys
    stay within 0.33 and 99 % of random colours within 1.2.
    """
    m = layer_matrix(film)
    grid = CubeLUT.identity(size).table
    linear = FLOG2.decode(grid)
    return CubeLUT(size, render(linear, film, settings, m), np.zeros(3), np.ones(3), title)
