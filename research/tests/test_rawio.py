import numpy as np
import pytest
from PIL import Image

from filmsim.rawio import crop_center, load_srgb, resize_linear


def test_crop_center_takes_the_middle():
    img = np.arange(6 * 8).reshape(6, 8)
    out = crop_center(img, 2, 4)
    np.testing.assert_array_equal(out, img[2:4, 2:6])


def test_crop_center_rejects_a_larger_crop():
    with pytest.raises(ValueError):
        crop_center(np.zeros((4, 4, 3)), 5, 4)


def test_resize_linear_averages_linear_light_without_quantising():
    img = np.zeros((4, 4, 3), dtype=np.float32)
    img[:, :2] = 0.001
    img[:, 2:] = 0.003
    out = resize_linear(img, (1, 1))
    assert out.shape == (1, 1, 3)
    np.testing.assert_allclose(out, 0.002, rtol=1e-5)


def test_resize_linear_keeps_channels_apart():
    img = np.zeros((6, 9, 3), dtype=np.float32)
    img[..., 0] = 0.1
    img[..., 2] = 0.9
    out = resize_linear(img, (3, 2))
    assert out.shape == (2, 3, 3)
    np.testing.assert_allclose(out[..., 0], 0.1, rtol=1e-5)
    np.testing.assert_allclose(out[..., 1], 0.0, atol=1e-7)
    np.testing.assert_allclose(out[..., 2], 0.9, rtol=1e-5)


def test_load_srgb_applies_exif_orientation(tmp_path):
    path = tmp_path / "portrait.jpg"
    exif = Image.Exif()
    exif[0x0112] = 6  # rotate 90° CW to display
    Image.new("RGB", (8, 4)).save(path, exif=exif)
    assert load_srgb(path).shape == (8, 4, 3)
