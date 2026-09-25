"""Minimal .cube (Adobe/Resolve 3D LUT) reader and trilinear applier."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import numpy as np


@dataclass
class CubeLUT:
    size: int
    table: np.ndarray  # shape (size, size, size, 3), indexed [r, g, b]
    domain_min: np.ndarray
    domain_max: np.ndarray
    title: str = ""

    @classmethod
    def identity(cls, size: int = 33) -> "CubeLUT":
        g = np.linspace(0.0, 1.0, size)
        r, gg, b = np.meshgrid(g, g, g, indexing="ij")
        return cls(size, np.stack([r, gg, b], axis=-1), np.zeros(3), np.ones(3), "identity")

    @classmethod
    def load(cls, path: str | Path) -> "CubeLUT":
        size = None
        title = ""
        dmin = np.zeros(3)
        dmax = np.ones(3)
        rows: list[list[float]] = []
        for raw in Path(path).read_text().splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            key, *rest = line.split()
            if key == "TITLE":
                title = " ".join(rest).strip('"')
            elif key == "LUT_3D_SIZE":
                size = int(rest[0])
            elif key == "LUT_1D_SIZE":
                raise ValueError("1D LUTs are not supported")
            elif key == "DOMAIN_MIN":
                dmin = np.array([float(v) for v in rest])
            elif key == "DOMAIN_MAX":
                dmax = np.array([float(v) for v in rest])
            else:
                rows.append([float(key)] + [float(v) for v in rest])
        if size is None:
            raise ValueError(f"{path}: LUT_3D_SIZE missing")
        data = np.asarray(rows, dtype=np.float64)
        if data.shape != (size ** 3, 3):
            raise ValueError(f"{path}: expected {size ** 3} rows, got {data.shape[0]}")
        # .cube order: red varies fastest, then green, then blue -> reshape as [b, g, r]
        table = data.reshape(size, size, size, 3).transpose(2, 1, 0, 3)
        return cls(size, table, dmin, dmax, title)

    def apply(self, img: np.ndarray) -> np.ndarray:
        """Trilinear interpolation on an (..., 3) float image in [domain_min, domain_max]."""
        n = self.size
        x = (np.asarray(img, dtype=np.float64) - self.domain_min) / (self.domain_max - self.domain_min)
        x = np.clip(x, 0.0, 1.0) * (n - 1)
        i0 = np.floor(x).astype(int)
        i0 = np.minimum(i0, n - 2)
        f = x - i0
        i1 = i0 + 1

        r0, g0, b0 = i0[..., 0], i0[..., 1], i0[..., 2]
        r1, g1, b1 = i1[..., 0], i1[..., 1], i1[..., 2]
        fr, fg, fb = (f[..., k][..., None] for k in range(3))

        t = self.table
        c00 = t[r0, g0, b0] * (1 - fr) + t[r1, g0, b0] * fr
        c10 = t[r0, g1, b0] * (1 - fr) + t[r1, g1, b0] * fr
        c01 = t[r0, g0, b1] * (1 - fr) + t[r1, g0, b1] * fr
        c11 = t[r0, g1, b1] * (1 - fr) + t[r1, g1, b1] * fr
        c0 = c00 * (1 - fg) + c10 * fg
        c1 = c01 * (1 - fg) + c11 * fg
        return c0 * (1 - fb) + c1 * fb
