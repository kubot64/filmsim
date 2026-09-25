"""Measurements for the iPhone exposure anchor (#6).

The anchor is the gain that puts the camera's metered middle grey at 18% before
F-Log2. A frame filled with one flat surface is metered to middle grey, so its
centre luminance gives the anchor directly. Only the centre is used: LibRaw does
not apply the lens-shading gain map in iPhone DNGs, and the corners differ from
CIRAWFilter by more than 1 EV.
"""

from __future__ import annotations

import numpy as np

from .gamut import RGBSpace

MIDDLE_GREY = 0.18


def center_region(img: np.ndarray, fraction: float = 0.4) -> np.ndarray:
    """The central `fraction` of the height and the width."""
    if not 0 < fraction <= 1:
        raise ValueError(f"fraction must be in (0, 1], got {fraction}")
    h, w = img.shape[:2]
    top, left = round(h * (1 - fraction) / 2), round(w * (1 - fraction) / 2)
    return img[top : h - top, left : w - left]


def luminance(rgb: np.ndarray, space: RGBSpace) -> np.ndarray:
    """CIE Y of linear RGB in `space`."""
    return rgb @ space.to_xyz()[1]


def metered_anchor_ev(center_luminance: float, grey: float = MIDDLE_GREY) -> float:
    """EV that moves a metered flat surface to `grey`. Meaningful only for flat frames."""
    return float(np.log2(grey / center_luminance))


def headroom_stops(raw_fraction: float) -> float:
    """Stops from a raw value (fraction of black-to-white range) up to sensor clipping."""
    return float(np.log2(1.0 / raw_fraction))
