from pathlib import Path

import colour
import numpy as np

from filmsim import portra400vc
from filmsim.cube import CubeLUT
from filmsim.flog2 import FLOG2
from filmsim.gamut import BT2020
from filmsim.negative import PORTRA_400VC, bake_lut, layer_matrix, render

COMMITTED = Path(__file__).parents[2] / "ios/FilmSim/LUTs/Portra400VC_33grid.cube"


def lch(srgb: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    lab = colour.XYZ_to_Lab(colour.sRGB_to_XYZ(srgb))
    return lab[..., 0], np.hypot(lab[..., 1], lab[..., 2]), np.degrees(np.arctan2(lab[..., 2], lab[..., 1])) % 360


def colorchecker_linear() -> np.ndarray:
    shape = colour.SpectralShape(400, 700, 10)
    cmfs = colour.MSDS_CMFS["CIE 1931 2 Degree Standard Observer"].copy().align(shape)
    d65 = colour.SDS_ILLUMINANTS["D65"].copy().align(shape)
    sds = colour.SDS_COLOURCHECKERS["ColorChecker N Ohta"].values()
    xyz = np.array([colour.sd_to_XYZ(sd.copy().align(shape), cmfs=cmfs, illuminant=d65) / 100 for sd in sds])
    return xyz @ BT2020.from_xyz().T


def test_layer_matrix_keeps_neutrals_neutral():
    m = layer_matrix(portra400vc)
    np.testing.assert_allclose(m @ np.ones(3), np.ones(3), atol=1e-12)


def test_greys_stay_neutral_from_black_to_white():
    stops = np.linspace(-7, 3, 41)
    grey = np.repeat((0.18 * 2.0 ** stops)[:, None], 3, axis=1)
    _, chroma, _ = lch(render(grey, portra400vc, PORTRA_400VC))
    assert chroma.max() < 1.0


def test_mid_grey_prints_near_18_percent():
    out = render(np.full(3, 0.18), portra400vc, PORTRA_400VC)
    y = colour.cctf_decoding(out, function="sRGB")
    np.testing.assert_allclose(y, 0.18, atol=0.01)


def test_tone_rises_monotonically():
    stops = np.linspace(-8, 4, 97)
    grey = np.repeat((0.18 * 2.0 ** stops)[:, None], 3, axis=1)
    out = render(grey, portra400vc, PORTRA_400VC)[:, 1]
    assert np.all(np.diff(out) >= 0)


def test_colorchecker_is_vivid_but_keeps_hues():
    """What the settings were tuned for: about 1.2x chroma, no hue moved by more than 10°."""
    lin = colorchecker_linear()
    true = colour.cctf_encoding(np.clip(colour.XYZ_to_sRGB(colour.RGB_to_XYZ(
        lin, colour.RGB_COLOURSPACES["ITU-R BT.2020"], apply_cctf_decoding=False),
        apply_cctf_encoding=False), 0, 1), function="sRGB")
    _, c_true, h_true = lch(true)
    _, c_out, h_out = lch(render(lin, portra400vc, PORTRA_400VC))
    chromatic = c_true > 15
    ratio = (c_out[chromatic] / c_true[chromatic]).mean()
    assert 1.1 < ratio < 1.35
    dh = (h_out - h_true + 180) % 360 - 180
    assert np.abs(dh[chromatic]).max() < 10


def test_committed_lut_matches_the_model():
    """ios/FilmSim/LUTs/Portra400VC_33grid.cube must be re-baked when the model changes."""
    committed = CubeLUT.load(COMMITTED)
    fresh = bake_lut(portra400vc, PORTRA_400VC, size=committed.size)
    np.testing.assert_allclose(committed.table, fresh.table, atol=2e-6)


def test_lut_takes_flog2_codes():
    lut = CubeLUT.load(COMMITTED)
    grey = lut.apply(np.full(3, FLOG2.encode(0.18)))
    np.testing.assert_allclose(colour.cctf_decoding(grey, function="sRGB"), 0.18, atol=0.01)
