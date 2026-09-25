import numpy as np

from filmsim.gamut import BT2020, BT709, F_GAMUT, P3_D65, apply_matrix, conversion_matrix


def test_fgamut_equals_bt2020():
    np.testing.assert_allclose(F_GAMUT.to_xyz(), BT2020.to_xyz(), atol=1e-12)


def test_bt709_matrix_matches_known_values():
    # Standard sRGB/BT.709 -> XYZ (D65) matrix
    expected = np.array([
        [0.4124, 0.3576, 0.1805],
        [0.2126, 0.7152, 0.0722],
        [0.0193, 0.1192, 0.9505],
    ])
    np.testing.assert_allclose(BT709.to_xyz(), expected, atol=2e-4)


def test_white_is_preserved_between_d65_spaces():
    m = conversion_matrix(P3_D65, F_GAMUT)
    np.testing.assert_allclose(apply_matrix(np.ones(3), m), np.ones(3), atol=1e-9)


def test_round_trip():
    m = conversion_matrix(P3_D65, F_GAMUT) @ conversion_matrix(F_GAMUT, P3_D65)
    np.testing.assert_allclose(m, np.eye(3), atol=1e-12)
