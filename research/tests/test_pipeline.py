import numpy as np

from filmsim import CubeLUT, Recipe, render
from filmsim.flog2 import FLOG2


def test_render_with_identity_lut_returns_flog2_encoding():
    img = np.full((4, 4, 3), 0.18)
    out = render(img, Recipe(film_sim="id"), {"id": CubeLUT.identity(33)})
    np.testing.assert_allclose(out, FLOG2.encode(0.18), atol=2e-3)


def test_exposure_ev_shifts_by_one_stop():
    img = np.full((2, 2, 3), 0.09)
    luts = {"id": CubeLUT.identity(65)}
    out = render(img, Recipe(film_sim="id", exposure_ev=1.0), luts)
    np.testing.assert_allclose(out, FLOG2.encode(0.18), atol=2e-3)


def test_grain_is_deterministic():
    rng = np.random.default_rng(1)
    img = rng.random((16, 16, 3))
    luts = {"id": CubeLUT.identity(17)}
    a = render(img, Recipe(film_sim="id", grain_strength="strong"), luts, seed=3)
    b = render(img, Recipe(film_sim="id", grain_strength="strong"), luts, seed=3)
    np.testing.assert_array_equal(a, b)
