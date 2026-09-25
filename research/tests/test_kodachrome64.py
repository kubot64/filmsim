from filmsim.kodachrome64 import LOG_EXPOSURE_LUX_SECONDS, SPECTRAL_DENSITY, STATUS_A, WAVELENGTH_NM


def test_characteristic_curve_is_reversal():
    assert len(LOG_EXPOSURE_LUX_SECONDS) == 29
    assert LOG_EXPOSURE_LUX_SECONDS[0] == -2.4
    assert LOG_EXPOSURE_LUX_SECONDS[-1] == 0.4
    for name, curve in STATUS_A.items():
        assert len(curve) == len(LOG_EXPOSURE_LUX_SECONDS), name
        assert curve == tuple(sorted(curve, reverse=True))
    # Labels sit on the shadow end in this order: R above G above B.
    assert STATUS_A["R"][0] > STATUS_A["G"][0] > STATUS_A["B"][0]


def test_dye_peaks():
    assert len(WAVELENGTH_NM) == 29
    assert WAVELENGTH_NM[0] == 420 and WAVELENGTH_NM[-1] == 700
    peaks = {name: WAVELENGTH_NM[curve.index(max(curve))] for name, curve in SPECTRAL_DENSITY.items()}
    assert peaks["yellow"] == 440
    assert peaks["magenta"] == 540
    assert peaks["cyan"] == 640
    assert peaks["neutral"] == 640
    assert max(SPECTRAL_DENSITY["yellow"][WAVELENGTH_NM.index(580):]) < 0.02
