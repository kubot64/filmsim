"""Hue rotation of warm colours in the LUT output (#11).

Against X-series camera JPEGs, the official (GFX-built) LUT renders reds and
oranges toward yellow, by the same amount whether the RAW is read with LibRaw or
CIRAWFilter, so it is not the RAW colour conversion. This rotates the chroma of
colours in a window around red/orange back toward red.

Works on the display-referred code values in BT.709 Y'CbCr: Y' and the chroma
length stay put, only the Cb/Cr angle changes. Hue angle h = atan2(Cr, Cb):
red is about 103 deg, orange (1, 0.5, 0) about 138 deg, yellow about 175 deg,
so a negative rotation moves toward red.
"""

from __future__ import annotations

import numpy as np

# Fixed rotation applied after the Provia LUT (#11). Fitted on seven Provia pairs
# (X100VI x4, X-T5 x3), read with both LibRaw and CIRAWFilter: reds/oranges/yellows
# rotate 7 deg back toward red. The window (140 +- 80 deg) stops short of green.
# Classic Chrome is left alone: its warm error is smaller, and a Provia-fitted rotation
# made two or three of seven Classic Chrome pairs worse overall (depending on engine).
WARM_HUE_DEGREES = -7.0
WARM_HUE_CENTER = 140.0
WARM_HUE_WIDTH = 80.0
WARM_HUE_FILM_SIMS = ("provia",)

_KR, _KB = 0.2126, 0.0722
_KG = 1 - _KR - _KB
_CB_SCALE = 2 * (1 - _KB)  # 1.8556
_CR_SCALE = 2 * (1 - _KR)  # 1.5748


def to_ycbcr(rgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    y = _KR * r + _KG * g + _KB * b
    return y, (b - y) / _CB_SCALE, (r - y) / _CR_SCALE


def from_ycbcr(y: np.ndarray, cb: np.ndarray, cr: np.ndarray) -> np.ndarray:
    r = y + _CR_SCALE * cr
    b = y + _CB_SCALE * cb
    g = (y - _KR * r - _KB * b) / _KG
    return np.stack([r, g, b], axis=-1)


def hue_degrees(rgb: np.ndarray) -> np.ndarray:
    _, cb, cr = to_ycbcr(np.asarray(rgb, dtype=np.float64))
    return np.degrees(np.arctan2(cr, cb)) % 360


def rotate_warm_hues(rgb: np.ndarray, degrees: float, center: float, width: float) -> np.ndarray:
    """Rotate hues within `width` degrees of `center` by up to `degrees`.

    The amount follows a raised cosine: `degrees` at `center`, 0 at center ± width.
    Neutral pixels (no chroma) do not move. The result is clipped to [0, 1].
    """
    rgb = np.clip(np.asarray(rgb, dtype=np.float64), 0.0, 1.0)
    y, cb, cr = to_ycbcr(rgb)
    h = np.degrees(np.arctan2(cr, cb))
    d = (h - center + 180) % 360 - 180
    w = np.where(np.abs(d) < width, 0.5 * (1 + np.cos(np.pi * d / width)), 0.0)
    t = np.radians(degrees) * w
    c, s = np.cos(t), np.sin(t)
    return np.clip(from_ycbcr(y, cb * c - cr * s, cb * s + cr * c), 0.0, 1.0)


def x_series_warm_hue(rgb: np.ndarray) -> np.ndarray:
    """The fixed warm-hue rotation with the fitted parameters."""
    return rotate_warm_hues(rgb, WARM_HUE_DEGREES, WARM_HUE_CENTER, WARM_HUE_WIDTH)
