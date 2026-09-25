"""RGB colour spaces and conversion matrices.

All spaces here share the D65 white point, so no chromatic adaptation is needed.
F-Gamut primaries are identical to ITU-R BT.2020 (F-Log2 data sheet section 3).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class RGBSpace:
    name: str
    red: tuple[float, float]
    green: tuple[float, float]
    blue: tuple[float, float]
    white: tuple[float, float]

    def to_xyz(self) -> np.ndarray:
        """3x3 matrix mapping linear RGB (this space) to CIE XYZ."""
        xy = np.array([self.red, self.green, self.blue], dtype=np.float64)
        xyz = np.column_stack([xy[:, 0], xy[:, 1], 1.0 - xy[:, 0] - xy[:, 1]]).T  # columns = R,G,B
        wx, wy = self.white
        w = np.array([wx / wy, 1.0, (1.0 - wx - wy) / wy])
        s = np.linalg.solve(xyz, w)
        return xyz * s

    def from_xyz(self) -> np.ndarray:
        return np.linalg.inv(self.to_xyz())


D65 = (0.31270, 0.32900)

F_GAMUT = RGBSpace("F-Gamut", (0.708, 0.292), (0.170, 0.797), (0.131, 0.046), D65)
BT2020 = RGBSpace("BT.2020", (0.708, 0.292), (0.170, 0.797), (0.131, 0.046), D65)
BT709 = RGBSpace("BT.709", (0.640, 0.330), (0.300, 0.600), (0.150, 0.060), D65)
P3_D65 = RGBSpace("Display P3", (0.680, 0.320), (0.265, 0.690), (0.150, 0.060), D65)


def conversion_matrix(src: RGBSpace, dst: RGBSpace) -> np.ndarray:
    """3x3 matrix converting linear RGB from src to dst."""
    return dst.from_xyz() @ src.to_xyz()


def apply_matrix(img: np.ndarray, m: np.ndarray) -> np.ndarray:
    """Apply a 3x3 matrix to an (..., 3) image."""
    return np.einsum("ij,...j->...i", m, img)
