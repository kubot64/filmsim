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


def test_warm_hue_fix_applies_to_provia_only():
    img = np.full((2, 2, 3), 0.0)
    img[..., 0], img[..., 1], img[..., 2] = 0.35, 0.12, 0.05  # a warm linear colour
    lut = {"provia": CubeLUT.identity(33), "classic_chrome": CubeLUT.identity(33)}
    provia = render(img, Recipe(film_sim="provia"), lut)
    chrome = render(img, Recipe(film_sim="classic_chrome"), lut)
    assert not np.allclose(provia, chrome)
    from filmsim.hue import x_series_warm_hue

    np.testing.assert_allclose(provia, x_series_warm_hue(chrome), atol=1e-12)


def test_film_sim_key_from_official_lut_names():
    from filmsim.cube import film_sim_key

    assert film_sim_key("luts/official/FLog2_to_PROVIA_65grid_V.1.00.cube") == "provia"
    assert film_sim_key("FLog2_to_CLASSIC-CHROME_65grid_V.1.00.cube") == "classic_chrome"
    assert film_sim_key("my.cube") == "lut"
