import numpy as np
import pytest

from filmsim.hue import from_ycbcr, hue_degrees, rotate_warm_hues, to_ycbcr


def test_ycbcr_round_trip():
    rgb = np.random.default_rng(0).random((50, 3))
    np.testing.assert_allclose(from_ycbcr(*to_ycbcr(rgb)), rgb, atol=1e-12)


def test_hue_angles_of_primaries():
    assert hue_degrees(np.array([1.0, 0, 0])) == pytest.approx(102.9, abs=0.1)
    assert hue_degrees(np.array([1.0, 0.5, 0])) == pytest.approx(138.4, abs=0.1)
    assert hue_degrees(np.array([1.0, 1, 0])) == pytest.approx(174.8, abs=0.1)


def test_zero_rotation_is_identity():
    rgb = np.random.default_rng(1).random((50, 3))
    np.testing.assert_allclose(rotate_warm_hues(rgb, 0, 120, 40), rgb, atol=1e-12)


def test_neutrals_and_colours_outside_the_window_stay_put():
    rgb = np.array([[0.5, 0.5, 0.5], [0.2, 0.3, 0.9], [0.1, 0.8, 0.3]])  # grey, blue, green
    np.testing.assert_allclose(rotate_warm_hues(rgb, -8, 120, 40), rgb, atol=1e-12)


def test_rotates_orange_toward_red_and_keeps_luma_and_chroma():
    orange = np.array([0.8, 0.45, 0.2])
    out = rotate_warm_hues(orange, -8, float(hue_degrees(orange)), 40)  # at the window centre: full -8
    assert hue_degrees(out) == pytest.approx(hue_degrees(orange) - 8, abs=0.05)
    y0, cb0, cr0 = to_ycbcr(orange)
    y1, cb1, cr1 = to_ycbcr(out)
    assert y1 == pytest.approx(y0, abs=1e-12)
    assert np.hypot(cb1, cr1) == pytest.approx(np.hypot(cb0, cr0), abs=1e-12)


def test_rotation_keeps_hue_order_inside_the_window():
    # The amount changes with hue; it must not fold neighbouring hues over each other.
    h = np.linspace(80, 200, 241)
    t = np.radians(h)
    y = np.full_like(h, 0.5)
    rgb = from_ycbcr(y, 0.1 * np.cos(t), 0.1 * np.sin(t))
    out_h = hue_degrees(rotate_warm_hues(rgb, -10, 130, 40))
    assert np.all(np.diff(out_h) > 0)


def test_fitted_rotation_golden_points():
    # Swift / Metal must reproduce these (BT.709 Y'CbCr, -7 deg, centre 140, width 80).
    from filmsim.hue import x_series_warm_hue

    cases = [
        ([0.8, 0.2, 0.1], [0.8144788117, 0.1906360983, 0.1501228138]),
        ([0.9, 0.55, 0.2], [0.9390028460, 0.5337492135, 0.2461296049]),
        ([0.7, 0.7, 0.2], [0.7288390912, 0.6909850233, 0.2043811709]),
        ([0.2, 0.4, 0.9], [0.2, 0.4, 0.9]),
        ([0.5, 0.5, 0.5], [0.5, 0.5, 0.5]),
    ]
    for rgb, expected in cases:
        np.testing.assert_allclose(x_series_warm_hue(np.array(rgb)), expected, atol=1e-9)
