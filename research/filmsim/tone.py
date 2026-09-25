"""Highlight / shadow tone adjustment.

Placeholder mapping of Fujifilm's -2..+4 scale onto a smooth curve applied to
display-referred (LUT output) values. There is no ground truth for how the real
camera bends the curve, so this is tuned by eye. See docs/OPEN_QUESTIONS.md.
"""

from __future__ import annotations

import numpy as np


def _smoothstep(edge0: float, edge1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - edge0) / (edge1 - edge0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


def tone_curve(x: np.ndarray, highlight: float = 0.0, shadow: float = 0.0) -> np.ndarray:
    """Apply highlight/shadow tone to a display-referred image in [0, 1].

    highlight, shadow: Fujifilm scale, -2 (softer) .. +4 (harder). 0 = no change.
    """
    x = np.clip(np.asarray(x, dtype=np.float64), 0.0, 1.0)
    out = x.copy()
    if highlight != 0.0:
        w = _smoothstep(0.5, 1.0, x)
        gamma = 1.0 - 0.12 * highlight  # + => steeper highlights
        out = out * (1 - w) + np.power(x, max(gamma, 0.2)) * w
    if shadow != 0.0:
        w = 1.0 - _smoothstep(0.0, 0.5, x)
        gamma = 1.0 + 0.12 * shadow  # + => deeper shadows
        out = out * (1 - w) + np.power(x, max(gamma, 0.2)) * w
    return np.clip(out, 0.0, 1.0)
