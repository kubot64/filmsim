"""Film-grain emulation: luminance-weighted monochrome noise."""

from __future__ import annotations

import numpy as np
from scipy.ndimage import gaussian_filter

STRENGTH = {"off": 0.0, "weak": 0.025, "strong": 0.05}
SIZE = {"small": 0.6, "large": 1.1}  # gaussian sigma in pixels at full resolution


def add_grain(img: np.ndarray, strength: str = "weak", size: str = "small", seed: int = 0) -> np.ndarray:
    """Add grain to a display-referred (..., 3) image in [0, 1]."""
    amp = STRENGTH[strength]
    if amp == 0.0:
        return img
    rng = np.random.default_rng(seed)
    h, w = img.shape[:2]
    noise = rng.standard_normal((h, w))
    noise = gaussian_filter(noise, SIZE[size])
    noise /= noise.std() + 1e-9
    lum = 0.2126 * img[..., 0] + 0.7152 * img[..., 1] + 0.0722 * img[..., 2]
    # more visible in midtones, fades in deep shadows and near white
    weight = np.sqrt(np.clip(lum, 0, 1)) * (1.0 - np.clip(lum, 0, 1)) * 2.0
    return np.clip(img + (noise * weight * amp)[..., None], 0.0, 1.0)
