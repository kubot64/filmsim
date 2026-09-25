"""End-to-end render: linear scene RGB -> Fujifilm look."""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np

from .cube import CubeLUT
from .flog2 import FLOG2
from .gamut import BT709, F_GAMUT, RGBSpace, apply_matrix, conversion_matrix
from .grain import add_grain
from .tone import tone_curve


@dataclass
class Recipe:
    film_sim: str = "provia"          # key into the LUT dict passed to render()
    exposure_ev: float = 0.0          # exposure anchor offset, decided by ΔE sweep
    wb_shift: tuple[float, float] = (0.0, 0.0)  # Fujifilm R/B shift, -9..+9
    highlight: float = 0.0            # -2..+4
    shadow: float = 0.0               # -2..+4
    grain_strength: str = "off"       # off / weak / strong
    grain_size: str = "small"         # small / large
    extra: dict = field(default_factory=dict)


def wb_shift_gains(r_shift: float, b_shift: float, step: float = 0.03) -> np.ndarray:
    """Fujifilm WB shift (-9..+9) -> linear RGB multipliers. Step size is a guess."""
    return np.array([1.0 + step * r_shift, 1.0, 1.0 + step * b_shift])


def srgb_encode(x: np.ndarray) -> np.ndarray:
    x = np.clip(x, 0.0, 1.0)
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


def render(
    linear: np.ndarray,
    recipe: Recipe,
    luts: dict[str, CubeLUT],
    input_space: RGBSpace = F_GAMUT,
    seed: int = 0,
) -> np.ndarray:
    """Render a scene-linear (H, W, 3) image to display-referred code values.

    The official LUTs take F-Log2 / F-Gamut in and produce BT.709-gamma out.
    `metrics.delta_e_stats` still decodes those codes with the sRGB EOTF.
    """
    x = np.asarray(linear, dtype=np.float64)
    x = x * wb_shift_gains(*recipe.wb_shift)
    x = x * (2.0 ** recipe.exposure_ev)
    if input_space is not F_GAMUT:
        x = apply_matrix(x, conversion_matrix(input_space, F_GAMUT))
    x = np.clip(x, 0.0, None)
    log = FLOG2.encode(x)
    out = luts[recipe.film_sim].apply(np.clip(log, 0.0, 1.0))
    out = tone_curve(out, recipe.highlight, recipe.shadow)
    out = add_grain(out, recipe.grain_strength, recipe.grain_size, seed=seed)
    return np.clip(out, 0.0, 1.0)


def bt709_to_srgb_matrix() -> np.ndarray:
    """Identity; kept so the call site documents the assumption explicitly."""
    return conversion_matrix(BT709, BT709)
