"""RAW / JPEG I/O helpers."""

from __future__ import annotations

from pathlib import Path

import numpy as np
import rawpy
from PIL import Image


def load_raw_linear(path: str | Path, space: str = "rec2020") -> np.ndarray:
    """Demosaic a RAF/DNG with LibRaw to scene-linear float32 in the given space.

    rec2020 == F-Gamut primaries, so the result can go straight into F-Log2.
    No auto-brightening, gamma 1.0, camera as-shot white balance.
    """
    cs = {"rec2020": rawpy.ColorSpace.Rec2020, "srgb": rawpy.ColorSpace.sRGB}[space]
    with rawpy.imread(str(path)) as raw:
        rgb16 = raw.postprocess(
            output_color=cs,
            gamma=(1.0, 1.0),
            no_auto_bright=True,
            use_camera_wb=True,
            output_bps=16,
            highlight_mode=rawpy.HighlightMode.Clip,
        )
    return rgb16.astype(np.float32) / 65535.0


def load_srgb(path: str | Path) -> np.ndarray:
    """Load an 8-bit sRGB image as encoded floats in [0, 1]."""
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0


def save_srgb(path: str | Path, img: np.ndarray) -> None:
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8)).save(path)


def crop_center(img: np.ndarray, height: int, width: int) -> np.ndarray:
    """Cut the central (height, width) region.

    LibRaw returns a few more rows and columns than the camera JPEG (e.g. X100VI
    7752x5178 vs 7728x5152). Comparing without this crop shifts every pixel and
    inflates ΔE at edges.
    """
    h, w = img.shape[:2]
    if height > h or width > w:
        raise ValueError(f"crop {width}x{height} is larger than image {w}x{h}")
    y, x = (h - height) // 2, (w - width) // 2
    return img[y : y + height, x : x + width]


def resize_linear(img: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    """Resize a scene-linear float image to (width, height) with a box filter.

    Stays in float, so averaging happens on linear light without 8-bit quantisation.
    """
    channels = [
        np.asarray(Image.fromarray(np.ascontiguousarray(img[..., c], dtype=np.float32)).resize(size, Image.Resampling.BOX))
        for c in range(img.shape[-1])
    ]
    return np.stack(channels, axis=-1)


def resize_to(img: np.ndarray, size: tuple[int, int]) -> np.ndarray:
    """Resize an encoded float image to (width, height) with a box filter."""
    pil = Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8))
    return np.asarray(pil.resize(size, Image.Resampling.BOX), dtype=np.float32) / 255.0
