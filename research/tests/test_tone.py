import numpy as np
import pytest

from filmsim.tone import tone_curve


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
