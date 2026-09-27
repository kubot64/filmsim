"""Fit a 3D LUT from pixel pairs, for looks that have no official LUT (e.g. Leica Standard).

The pairs are F-Log2 codes of a RAW (input) and the camera JPEG's code values (output).
The LUT is the table whose trilinear lookup best matches them, which is a sparse linear
least-squares problem in the table entries. Most of the cube never appears in real photos
(saturated colours, extreme hues), so a smoothness term fills it: second differences along
each axis are penalised, which extends the fitted correction smoothly instead of leaving
holes. Both terms act on the difference from `prior` (identity by default), so the fit is
"prior plus a smooth correction": where the photos say nothing, the correction learned
nearby carries on smoothly, and data that agrees with the prior leaves it untouched.
A small ridge keeps the system well-posed.

Fit at 33: 33³ unknowns solve in seconds, 65³ does not, and real photos do not constrain
the finer grid anyway. The app reads any grid size, so the 33 file ships as is.
"""

from __future__ import annotations

import numpy as np
from scipy import sparse
from scipy.sparse.linalg import spsolve

from .cube import CubeLUT

# Pairs are averaged into cells this fine before fitting. Millions of pixels become tens
# of thousands of rows, and the fit barely changes: each cell is much smaller than a LUT cell.
BIN_CELLS = 128


def bin_pairs(x: np.ndarray, y: np.ndarray, cells: int = BIN_CELLS) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Average (N, 3) inputs and outputs per input cell. Returns (x, y, pixel count)."""
    x = np.clip(np.asarray(x, dtype=np.float64).reshape(-1, 3), 0.0, 1.0)
    y = np.asarray(y, dtype=np.float64).reshape(-1, 3)
    q = np.minimum((x * cells).astype(np.int64), cells - 1)
    key = (q[:, 0] * cells + q[:, 1]) * cells + q[:, 2]
    _, inverse, counts = np.unique(key, return_inverse=True, return_counts=True)
    xs = np.zeros((counts.size, 3))
    ys = np.zeros((counts.size, 3))
    np.add.at(xs, inverse, x)
    np.add.at(ys, inverse, y)
    return xs / counts[:, None], ys / counts[:, None], counts.astype(np.float64)


def _trilinear_matrix(x: np.ndarray, size: int) -> sparse.csr_matrix:
    """(N, size³) matrix whose product with a flattened [r, g, b] table is CubeLUT.apply."""
    p = np.clip(x, 0.0, 1.0) * (size - 1)
    i0 = np.minimum(np.floor(p).astype(np.int64), size - 2)
    f = p - i0
    rows, cols, vals = [], [], []
    n = x.shape[0]
    for dr in (0, 1):
        for dg in (0, 1):
            for db in (0, 1):
                w = (
                    (f[:, 0] if dr else 1 - f[:, 0])
                    * (f[:, 1] if dg else 1 - f[:, 1])
                    * (f[:, 2] if db else 1 - f[:, 2])
                )
                idx = ((i0[:, 0] + dr) * size + (i0[:, 1] + dg)) * size + (i0[:, 2] + db)
                rows.append(np.arange(n))
                cols.append(idx)
                vals.append(w)
    return sparse.csr_matrix(
        (np.concatenate(vals), (np.concatenate(rows), np.concatenate(cols))), shape=(n, size ** 3)
    )


def _second_differences(size: int) -> sparse.csr_matrix:
    """Stacked second differences along r, g and b on the flattened [r, g, b] grid."""
    d2 = sparse.diags([1.0, -2.0, 1.0], [0, 1, 2], shape=(size - 2, size))
    eye = sparse.identity(size)
    along_r = sparse.kron(sparse.kron(d2, eye), eye)
    along_g = sparse.kron(sparse.kron(eye, d2), eye)
    along_b = sparse.kron(sparse.kron(eye, eye), d2)
    return sparse.vstack([along_r, along_g, along_b]).tocsr()


def fit_lut(
    x: np.ndarray,
    y: np.ndarray,
    size: int = 33,
    smoothness: float = 1e-3,
    prior: CubeLUT | None = None,
    ridge: float = 1e-6,
    weights: np.ndarray | None = None,
    title: str = "fitted",
) -> CubeLUT:
    """Least-squares LUT for inputs `x` and outputs `y`, both (N, 3) in [0, 1].

    `smoothness` and `ridge` are relative to the total sample weight per grid node, so
    they mean the same thing for 10k or 10M samples.
    """
    x = np.asarray(x, dtype=np.float64).reshape(-1, 3)
    y = np.asarray(y, dtype=np.float64).reshape(-1, 3)
    w = np.ones(x.shape[0]) if weights is None else np.asarray(weights, dtype=np.float64)
    if prior is None:
        prior = CubeLUT.identity(size)
    elif prior.size != size:
        prior = resample(prior, size)
    nodes = size ** 3
    scale = w.sum() / nodes

    a = _trilinear_matrix(x, size)
    aw = a.multiply(w[:, None]).tocsr()
    d = _second_differences(size)
    reg = smoothness * scale * (d.T @ d) + ridge * scale * sparse.identity(nodes)
    lhs = (a.T @ aw + reg).tocsc()

    # min |A t - y|²_w + (t - p)ᵀ R (t - p)  →  (AᵀWA + R) t = AᵀW y + R p
    prior_flat = prior.table.reshape(nodes, 3)
    table = np.empty((nodes, 3))
    for c in range(3):
        rhs = aw.T @ y[:, c] + reg @ prior_flat[:, c]
        table[:, c] = spsolve(lhs, rhs)
    return CubeLUT(size, table.reshape(size, size, size, 3), np.zeros(3), np.ones(3), title)


def resample(lut: CubeLUT, size: int) -> CubeLUT:
    """The same mapping on a `size` grid, by trilinear lookup of `lut` at the new nodes.

    Assumes the [0, 1] domain that the F-Log2 LUTs use.
    """
    grid = CubeLUT.identity(size).table
    return CubeLUT(size, lut.apply(grid), lut.domain_min.copy(), lut.domain_max.copy(), lut.title)
