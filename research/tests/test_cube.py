import numpy as np

from filmsim.cube import CubeLUT


def test_identity_lut_is_identity():
    lut = CubeLUT.identity(17)
    rng = np.random.default_rng(0)
    img = rng.random((8, 8, 3))
    np.testing.assert_allclose(lut.apply(img), img, atol=1e-12)


def test_parse_cube_text(tmp_path):
    # 2x2x2 LUT that swaps R and B; red varies fastest in .cube order
    lines = ["TITLE \"swap\"", "LUT_3D_SIZE 2"]
    for b in (0, 1):
        for g in (0, 1):
            for r in (0, 1):
                lines.append(f"{b} {g} {r}")
    p = tmp_path / "swap.cube"
    p.write_text("\n".join(lines) + "\n")
    lut = CubeLUT.load(p)
    assert lut.title == "swap"
    np.testing.assert_allclose(lut.apply(np.array([1.0, 0.0, 0.0])), [0.0, 0.0, 1.0])
    np.testing.assert_allclose(lut.apply(np.array([0.25, 0.5, 0.75])), [0.75, 0.5, 0.25])
