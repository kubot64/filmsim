"""ΔE2000 comparison between rendered output and the camera's OOC JPEG."""

from __future__ import annotations

import colour
import numpy as np


def srgb_to_lab(img: np.ndarray) -> np.ndarray:
    lin = colour.models.eotf_sRGB(np.clip(img, 0, 1))
    xyz = colour.RGB_to_XYZ(lin, colour.models.RGB_COLOURSPACE_sRGB, apply_cctf_decoding=False)
    return colour.XYZ_to_Lab(xyz)


def delta_e_stats(a: np.ndarray, b: np.ndarray) -> dict[str, float]:
    """Both inputs: sRGB-encoded floats of identical shape."""
    de = colour.delta_E(srgb_to_lab(a), srgb_to_lab(b), method="CIE 2000")
    return {
        "mean": float(de.mean()),
        "median": float(np.median(de)),
        "p95": float(np.percentile(de, 95)),
        "max": float(de.max()),
    }
