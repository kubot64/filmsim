import numpy as np
import pytest
from scipy.ndimage import gaussian_filter

from filmsim.grain import add_grain, grain_weight, unit_noise_gain


def test_weight_fades_at_extremes():
    assert grain_weight(0.0) == 0
    assert grain_weight(1.0) == 0
    np.testing.assert_allclose(grain_weight(0.25), 0.75)
    assert grain_weight(0.02) < grain_weight(0.4)
    assert grain_weight(0.98) < grain_weight(0.4)


def test_off_is_unchanged():
    img = np.full((8, 8, 3), 0.4)
    np.testing.assert_array_equal(add_grain(img, "off", "small", seed=0), img)


def test_amplitude_follows_weight():
    black = np.zeros((64, 64, 3))
    mid = np.full((64, 64, 3), 0.4)
    white = np.ones((64, 64, 3))

    def energy(img):
        return np.mean(np.abs(add_grain(img, "strong", "small", seed=1) - img))

    assert energy(mid) > energy(black)
    assert energy(mid) > energy(white)
    assert energy(black) == 0
    assert energy(white) == 0


def test_unit_noise_gain_matches_swift_constants():
    # Locked to GrainTests.testUnitNoiseGainMatchesScipyKernel.
    assert unit_noise_gain(0.6) == pytest.approx(6.991621, abs=1e-4)
    assert unit_noise_gain(1.1) == pytest.approx(13.507091, abs=1e-4)


def test_unit_noise_gain_matches_empirical_blur():
    rng = np.random.default_rng(0)
    for sigma in (0.6, 1.1):
        blurred = gaussian_filter(rng.random((800, 800)) - 0.5, sigma)
        assert unit_noise_gain(sigma) == pytest.approx(1.0 / float(blurred.std()), rel=0.01)
