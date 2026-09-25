import numpy as np

from filmsim.metrics import delta_e_breakdown


def _ramp() -> np.ndarray:
    grey = np.linspace(0.05, 0.95, 64)
    return np.repeat(np.repeat(grey[None, :, None], 64, axis=0), 3, axis=2)


def test_breakdown_is_zero_for_identical_images():
    img = _ramp()
    for r in delta_e_breakdown(img, img):
        assert r["median"] == 0
        assert r["dL"] == 0


def test_breakdown_reports_a_brighter_render_as_positive_lightness():
    ref = _ramp()
    rows = delta_e_breakdown(np.clip(ref + 0.05, 0, 1), ref)
    mid = next(r for r in rows if r["band"] == "L* 40-60")
    assert mid["dL"] > 0
    assert next(r for r in rows if r["band"] == "neutral")["share"] == 1.0
