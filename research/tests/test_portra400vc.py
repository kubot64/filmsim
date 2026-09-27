import numpy as np

from filmsim import portra400vc as vc


def test_tables_line_up():
    n = len(vc.LOG_EXPOSURE_LUX_SECONDS)
    assert all(len(v) == n for v in vc.STATUS_M.values())
    m = len(vc.DYE_WAVELENGTH_NM)
    assert all(len(v) == m for v in vc.DYE_DENSITY.values())


def test_negative_density_rises_with_exposure():
    for d in vc.STATUS_M.values():
        assert np.all(np.diff(d) > 0)


def test_d_min_order_and_straight_line_gamma():
    """Blue carries the orange mask, so B > G > R at the toe; VC's gamma is about 0.6."""
    b, g, r = (np.array(vc.STATUS_M[k]) for k in "BGR")
    assert b[0] > g[0] > r[0]
    logh = np.array(vc.LOG_EXPOSURE_LUX_SECONDS)
    straight = (logh >= -2.0) & (logh <= 0.0)
    for d in (b, g, r):
        slope = np.polyfit(logh[straight], d[straight], 1)[0]
        assert 0.55 < slope < 0.7


def test_reference_exposure_is_on_the_straight_line():
    logh = np.array(vc.LOG_EXPOSURE_LUX_SECONDS)
    assert logh[0] < vc.LOG_H_REF - 1.5 and vc.LOG_H_REF + 1.5 < logh[-1]


def test_mid_scale_neutral_is_denser_than_d_min():
    mid = np.array(vc.DYE_DENSITY["midscale_neutral"])
    dmin = np.array(vc.DYE_DENSITY["d_min"])
    assert np.all(mid > dmin)


def test_layer_sensitivity_peaks():
    peaks = {k: max(v, key=v.get) for k, v in vc.LOG_SENSITIVITY.items()}
    assert 390 <= peaks["yellow_forming"] <= 480
    assert 530 <= peaks["magenta_forming"] <= 560
    assert 610 <= peaks["cyan_forming"] <= 640
