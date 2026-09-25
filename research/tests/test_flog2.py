import numpy as np

from filmsim.flog2 import FLOG, FLOG2


def test_flog2_reference_points_from_datasheet():
    # F-Log2 Data Sheet Ver.1.1 section 2-2: 0% -> 95, 18% -> 400, 90% -> 570 (10bit)
    assert abs(FLOG2.encode(0.0) * 1023 - 95) < 1.0
    assert abs(FLOG2.encode(0.18) * 1023 - 400) < 1.0
    assert abs(FLOG2.encode(0.90) * 1023 - 570) < 1.0


def test_flog_reference_points_from_datasheet():
    # F-Log Data Sheet Ver.1.2: 18% -> 470, 90% -> 705 (10bit)
    assert abs(FLOG.encode(0.18) * 1023 - 470) < 1.5
    assert abs(FLOG.encode(0.90) * 1023 - 705) < 1.5


def test_flog2_round_trip():
    x = np.logspace(-4, 1, 200)
    np.testing.assert_allclose(FLOG2.decode(FLOG2.encode(x)), x, rtol=1e-6)


def test_flog2_continuous_at_cut():
    eps = 1e-9
    below = FLOG2.encode(FLOG2.cut1 - eps)
    above = FLOG2.encode(FLOG2.cut1 + eps)
    assert abs(below - above) < 1e-3
