import numpy as np
import pytest

from filmsim.tone import tone_curve, x_series_shoulder


def test_zero_is_identity():
    x = np.linspace(0, 1, 9)
    np.testing.assert_allclose(tone_curve(x, 0, 0), x)


def test_endpoints_and_midpoint_stay_put():
    # smoothstep weights are 0 at 0, 0.5, and 1, so both controls are no-ops there.
    for x in (0.0, 0.5, 1.0):
        assert tone_curve(np.array([x]), highlight=4, shadow=4)[0] == pytest.approx(x)


def test_positive_highlight_lifts_and_positive_shadow_deepens():
    # Eye-tuned polarity from tone.py. Positive highlight opens the shoulder;
    # positive shadow pushes the toe down.
    assert tone_curve(np.array([0.75]), highlight=4)[0] > 0.75
    assert tone_curve(np.array([0.25]), shadow=4)[0] < 0.25


def test_golden_points():
    cases = [
        (0.75, 4, 0, 0.805528455647),
        (0.25, 0, 4, 0.189257114166),
        (0.75, -2, 0, 0.724982211387),
        (0.25, 0, -2, 0.299342958294),
        (0.8, 2, 3, 0.828519484754),
    ]
    for x, highlight, shadow, expected in cases:
        got = tone_curve(np.array([x]), highlight=highlight, shadow=shadow)[0]
        assert got == pytest.approx(expected, abs=1e-12)


def test_output_stays_in_range():
    x = np.linspace(0, 1, 21)
    out = tone_curve(x, highlight=4, shadow=-2)
    assert out.min() >= 0 and out.max() <= 1


def _grey(v: float) -> np.ndarray:
    return np.array([[v, v, v]])


def test_shoulder_leaves_the_knee_and_below_alone_and_keeps_white():
    for v in (0.0, 0.2, 0.45, 0.6, 1.0):
        np.testing.assert_allclose(x_series_shoulder(_grey(v)), _grey(v), atol=1e-12)


def test_shoulder_lifts_highlights_monotonically():
    v = np.linspace(0, 1, 101)
    y = x_series_shoulder(np.stack([v, v, v], axis=-1))[:, 0]
    assert np.all(np.diff(y) >= 0)
    assert np.all(y[v > 0.6 + 1e-9][:-1] > v[v > 0.6 + 1e-9][:-1])


def test_shoulder_keeps_rgb_ratios():
    rgb = np.array([[0.9, 0.6, 0.5]])
    out = x_series_shoulder(rgb)[0]
    np.testing.assert_allclose(out / out[0], rgb[0] / rgb[0, 0], atol=1e-12)


def test_shoulder_golden_points():
    # Swift / Metal must reproduce these (knee 0.6, gamma 0.5, BT.709 luma).
    for v, expected in [(0.7, 0.721353129146), (0.8, 0.8472135955), (0.9, 0.94107653273), (0.95, 0.973618990031)]:
        assert x_series_shoulder(_grey(v))[0, 0] == pytest.approx(expected, abs=1e-11)
