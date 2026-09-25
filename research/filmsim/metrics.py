"""ΔE2000 comparison between rendered output and the camera's OOC JPEG."""

from __future__ import annotations

import colour
import numpy as np


def srgb_to_lab(img: np.ndarray) -> np.ndarray:
    lin = colour.models.eotf_sRGB(np.clip(img, 0, 1))
    xyz = colour.RGB_to_XYZ(lin, colour.models.RGB_COLOURSPACE_sRGB, apply_cctf_decoding=False)
    return colour.XYZ_to_Lab(xyz)


def delta_e_stats(a: np.ndarray, b: np.ndarray) -> dict[str, float]:
    """Both inputs are decoded with the sRGB EOTF.

    The camera JPEG is sRGB, and our code values are shown and saved as sRGB too
    (docs/DESIGN.md, #13), so both sides use the same curve.
    """
    de = colour.delta_E(srgb_to_lab(a), srgb_to_lab(b), method="CIE 2000")
    return {
        "mean": float(de.mean()),
        "median": float(np.median(de)),
        "p95": float(np.percentile(de, 95)),
        "max": float(de.max()),
    }


LIGHTNESS_BANDS = [(0, 20), (20, 40), (40, 60), (60, 80), (80, 90), (90, 101)]
HUE_BANDS = [
    ("red", 0, 40), ("orange", 40, 70), ("yellow", 70, 100), ("green", 100, 160),
    ("cyan", 160, 220), ("blue", 220, 290), ("magenta", 290, 360),
]


def delta_e_breakdown(a: np.ndarray, b: np.ndarray, min_share: float = 0.002) -> list[dict]:
    """Split ΔE by the reference's lightness and hue, and say which way `a` is off.

    `b` is the reference (camera JPEG). Each row gives the band's share of pixels,
    median ΔE2000 and the median differences a − b in L*, C* and hue angle (degrees,
    only over pixels with reference C* > 10). Hue bands only count pixels with
    reference C* > 20; "neutral" is C* < 5. Bands under `min_share` of the pixels are left out.
    """
    la = srgb_to_lab(a).reshape(-1, 3)
    lb = srgb_to_lab(b).reshape(-1, 3)
    de = colour.delta_E(la, lb, method="CIE 2000")
    ca, cb = np.hypot(la[:, 1], la[:, 2]), np.hypot(lb[:, 1], lb[:, 2])
    ha = np.degrees(np.arctan2(la[:, 2], la[:, 1])) % 360
    hb = np.degrees(np.arctan2(lb[:, 2], lb[:, 1])) % 360
    dh = (ha - hb + 180) % 360 - 180
    min_pixels = max(1, round(min_share * len(de)))

    def row(band: str, mask: np.ndarray) -> dict | None:
        if mask.sum() < min_pixels:
            return None
        chromatic = mask & (cb > 10)
        return {
            "band": band,
            "share": float(mask.mean()),
            "median": float(np.median(de[mask])),
            "dL": float(np.median(la[mask, 0] - lb[mask, 0])),
            "dC": float(np.median(ca[mask] - cb[mask])),
            "dh": float(np.median(dh[chromatic])) if chromatic.sum() >= max(1, min_pixels // 2) else float("nan"),
        }

    rows = [row(f"L* {lo}-{hi}", (lb[:, 0] >= lo) & (lb[:, 0] < hi)) for lo, hi in LIGHTNESS_BANDS]
    rows += [row(name, (cb > 20) & (hb >= lo) & (hb < hi)) for name, lo, hi in HUE_BANDS]
    rows.append(row("neutral", cb < 5))
    return [r for r in rows if r is not None]
