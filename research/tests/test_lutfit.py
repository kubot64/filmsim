import numpy as np

from filmsim.cube import CubeLUT
from filmsim.lutfit import bin_pairs, fit_lut, resample


def smooth_look(x: np.ndarray) -> np.ndarray:
    """A made-up look: contrast curve plus a little channel crosstalk."""
    m = np.array([[1.10, -0.07, -0.03], [-0.04, 1.06, -0.02], [-0.02, -0.08, 1.10]])
    return np.clip((x**0.9) @ m.T, 0.0, 1.0)


def test_save_load_round_trip(tmp_path):
    rng = np.random.default_rng(0)
    lut = CubeLUT(5, rng.random((5, 5, 5, 3)), np.zeros(3), np.ones(3), "round trip")
    path = tmp_path / "t.cube"
    lut.save(path)
    back = CubeLUT.load(path)
    assert back.size == 5 and back.title == "round trip"
    np.testing.assert_allclose(back.table, lut.table, atol=1e-6)


def test_fit_recovers_a_known_look():
    rng = np.random.default_rng(1)
    x = rng.random((60_000, 3))
    lut = fit_lut(x, smooth_look(x), size=17)
    test = rng.random((5_000, 3))
    err = np.abs(lut.apply(test) - smooth_look(test))
    assert np.percentile(err, 99) < 0.01


def test_data_that_agrees_with_the_prior_leaves_it_alone():
    """Only the grey-ish middle is observed; the rest of the cube must stay on the prior."""
    rng = np.random.default_rng(2)
    prior = resample(
        CubeLUT(9, smooth_look(CubeLUT.identity(9).table), np.zeros(3), np.ones(3)), 17
    )
    x = 0.4 + 0.2 * rng.random((20_000, 3))
    lut = fit_lut(x, prior.apply(x), size=17, prior=prior)
    corners = CubeLUT.identity(3).table.reshape(-1, 3)
    np.testing.assert_allclose(lut.apply(corners), prior.apply(corners), atol=0.01)


def test_unobserved_colours_stay_finite_and_in_range():
    rng = np.random.default_rng(3)
    x = 0.3 + 0.4 * rng.random((20_000, 3))
    lut = fit_lut(x, smooth_look(x), size=17)
    assert np.isfinite(lut.table).all()
    assert lut.table.min() > -0.2 and lut.table.max() < 1.2


def test_binning_keeps_the_fit():
    rng = np.random.default_rng(4)
    x = rng.random((200_000, 3))
    y = smooth_look(x) + rng.normal(0, 0.01, x.shape)
    xb, yb, counts = bin_pairs(x, y)
    assert counts.sum() == x.shape[0] and xb.shape[0] < x.shape[0]
    full = fit_lut(x, y, size=9)
    binned = fit_lut(xb, yb, size=9, weights=counts)
    np.testing.assert_allclose(binned.table, full.table, atol=0.005)


def test_resample_keeps_the_mapping():
    lut = CubeLUT(9, smooth_look(CubeLUT.identity(9).table), np.zeros(3), np.ones(3))
    fine = resample(lut, 33)
    x = np.random.default_rng(5).random((1_000, 3))
    np.testing.assert_allclose(fine.apply(x), lut.apply(x), atol=1e-9)
