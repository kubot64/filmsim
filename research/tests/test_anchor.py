import numpy as np
import pytest

from filmsim.anchor import center_region, headroom_stops, luminance, metered_anchor_ev
from filmsim.gamut import BT2020, P3_D65


def test_center_region_takes_the_middle():
    img = np.arange(10 * 20).reshape(10, 20)
    out = center_region(img, 0.4)
    np.testing.assert_array_equal(out, img[3:7, 6:14])


def test_center_region_rejects_a_bad_fraction():
    with pytest.raises(ValueError):
        center_region(np.zeros((4, 4)), 0)


@pytest.mark.parametrize("space", [P3_D65, BT2020])
def test_luminance_of_white_is_one_and_weights_match_the_space(space):
    assert luminance(np.ones(3), space) == pytest.approx(1.0)
    # Published Y weights: Display P3 0.2290/0.6917/0.0793, BT.2020 0.2627/0.6780/0.0593.
    expected = {P3_D65: [0.2290, 0.6917, 0.0793], BT2020: [0.2627, 0.6780, 0.0593]}[space]
    np.testing.assert_allclose(luminance(np.eye(3), space), expected, atol=1e-4)


def test_metered_anchor_ev():
    assert metered_anchor_ev(0.18) == pytest.approx(0.0)
    assert metered_anchor_ev(0.36) == pytest.approx(-1.0)
    # The white wall of #6: centre Y 0.231 in CIRAWFilter linear.
    assert metered_anchor_ev(0.231) == pytest.approx(-0.36, abs=0.005)


def test_headroom_stops():
    assert headroom_stops(0.25) == pytest.approx(2.0)
    assert headroom_stops(1.0) == pytest.approx(0.0)
