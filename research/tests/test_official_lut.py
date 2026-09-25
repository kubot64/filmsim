from pathlib import Path

import numpy as np
import pytest

from filmsim.cube import CubeLUT
from filmsim.flog2 import FLOG2

OFFICIAL = Path(__file__).resolve().parents[1] / "luts" / "official"
PROVIA = OFFICIAL / "FLog2_to_PROVIA_65grid_V.1.00.cube"


@pytest.mark.skipif(not PROVIA.exists(), reason="run scripts/fetch_luts.sh to get the official LUTs")
def test_official_provia_maps_grey_sensibly():
    lut = CubeLUT.load(PROVIA)
    assert lut.size == 65
    black = lut.apply(FLOG2.encode(np.zeros(3)))
    grey = lut.apply(FLOG2.encode(np.full(3, 0.18)))
    white = lut.apply(FLOG2.encode(np.full(3, 0.90)))
    # neutral in, neutral out
    for v in (black, grey, white):
        assert np.ptp(v) < 0.03, v
    # monotonic and 18% grey lands around mid-tone in BT.709 gamma
    assert black.mean() < grey.mean() < white.mean()
    assert 0.35 < grey.mean() < 0.6, grey
