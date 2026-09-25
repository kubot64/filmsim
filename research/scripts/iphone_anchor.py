"""Measure iPhone DNGs for the exposure anchor and render them at candidate EVs (#6).

Example:
    uv run python scripts/iphone_anchor.py samples/iphone/*.DNG --ev 0 -0.35 --libraw

Per DNG it prints the EXIF, the centre luminance of the CIRAWFilter linear image,
the anchor that would put the centre at 18% (meaningful only for a frame filled
with one flat surface, which the camera meters to middle grey), and the raw
headroom above the centre. Every DNG is rendered through the LUT at each --ev and
laid out in one contact sheet, one row per DNG.

The linear image comes from CIRAWFilter (scripts/ci_linear.swift, same settings as
RawDeveloper.developLinear), so this runs on macOS only. The helper is compiled
into out/bin on first use.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np
import rawpy
from PIL import Image, ImageDraw

from filmsim import BT2020, P3_D65, CubeLUT, Recipe, render
from filmsim.anchor import MIDDLE_GREY, center_region, headroom_stops, luminance, metered_anchor_ev
from filmsim.rawio import load_raw_linear, resize_linear

HERE = Path(__file__).resolve().parent
RESEARCH = HERE.parent
HELPER_SRC = HERE / "ci_linear.swift"
HELPER_BIN = RESEARCH / "out" / "bin" / "ci_linear"
DEFAULT_LUT = RESEARCH / "luts" / "official" / "FLog2_to_PROVIA_65grid_V.1.00.cube"
SHEET_WIDTH = 480


def helper() -> Path:
    if not HELPER_BIN.exists() or HELPER_BIN.stat().st_mtime < HELPER_SRC.stat().st_mtime:
        HELPER_BIN.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["swiftc", "-O", "-o", str(HELPER_BIN), str(HELPER_SRC)], check=True)
    return HELPER_BIN


def ci_linear(path: Path) -> tuple[np.ndarray, dict]:
    """Upright linear Display P3 image from CIRAWFilter, plus size and EXIF."""
    with tempfile.NamedTemporaryFile(suffix=".f32") as tmp:
        out = subprocess.run([str(helper()), str(path), tmp.name], check=True, capture_output=True, text=True)
        info = json.loads(out.stdout)
        img = np.fromfile(tmp.name, dtype=np.float32).reshape(info["height"], info["width"], 3)
    return img, info


def raw_green_center(path: Path) -> float:
    """Median of the green photosites in the centre, as a fraction of black-to-white."""
    with rawpy.imread(str(path)) as raw:
        vis = raw.raw_image_visible.astype(np.float32)
        colors = raw.raw_colors_visible
        black = float(np.mean(raw.black_level_per_channel))
        white = float(raw.white_level)
    v, c = center_region(vis), center_region(colors)
    green = v[(c == 1) | (c == 3)]
    return (float(np.median(green)) - black) / (white - black)


def label(img: Image.Image, text: str) -> Image.Image:
    ImageDraw.Draw(img).text((8, 8), text, fill=(255, 0, 0))
    return img


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("dng", nargs="+", type=Path)
    ap.add_argument("--ev", nargs="+", type=float, default=[0.0, -0.35], help="anchors to render")
    ap.add_argument("--lut", type=Path, default=DEFAULT_LUT)
    ap.add_argument("--out", type=Path, default=RESEARCH / "out" / "iphone_anchor")
    ap.add_argument("--libraw", action="store_true", help="also print the centre ratio against LibRaw")
    args = ap.parse_args()

    luts = {"lut": CubeLUT.load(args.lut)}
    grey = render(np.full((1, 1, 3), MIDDLE_GREY), Recipe(film_sim="lut"), luts, input_space=P3_D65)[0, 0, 0]
    print(f"reference: linear {MIDDLE_GREY:.0%} renders to sRGB {grey * 255:.0f}")

    rows = []
    for path in args.dng:
        linear, info = ci_linear(path)
        y = float(np.median(luminance(center_region(linear), P3_D65)))
        raw_g = raw_green_center(path)
        e = info["exif"]
        line = (
            f"{path.name}: {info['width']}x{info['height']} "
            f"1/{1 / e['exposure_time']:.0f}s f/{e['f_number']:.2f} ISO {e['iso']} bias {e.get('exposure_bias', 0):+g} | "
            f"centre Y {y:.4f}, flat-frame anchor {metered_anchor_ev(y):+.2f} EV, "
            f"raw green {raw_g:.3f} -> {headroom_stops(raw_g):.2f} stops to clip"
        )
        if args.libraw:
            lib_y = float(np.median(luminance(center_region(load_raw_linear(path)), BT2020)))
            line += f" | CIRAWFilter vs LibRaw centre {np.log2(y / lib_y):+.2f} EV"
        print(line)

        size = (SHEET_WIDTH, round(SHEET_WIDTH * linear.shape[0] / linear.shape[1]))
        small = resize_linear(linear, size)
        row = []
        for ev in args.ev:
            out = render(small, Recipe(film_sim="lut", exposure_ev=ev), luts, input_space=P3_D65)
            centre = np.median(center_region(out).reshape(-1, 3), axis=0) * 255
            print(f"    ev {ev:+.2f}: centre sRGB {centre[0]:.0f},{centre[1]:.0f},{centre[2]:.0f}")
            row.append(label(Image.fromarray((out * 255 + 0.5).astype(np.uint8)), f"{path.stem}  EV {ev:+.2f}"))
        rows.append(row)

    gap = 8
    w = SHEET_WIDTH
    heights = [row[0].height for row in rows]
    sheet = Image.new("RGB", (len(args.ev) * (w + gap) - gap, sum(heights) + gap * (len(rows) - 1)), "white")
    top = 0
    for row, h in zip(rows, heights):
        for i, img in enumerate(row):
            sheet.paste(img, (i * (w + gap), top))
        top += h + gap
    args.out.mkdir(parents=True, exist_ok=True)
    sheet_path = args.out / "sheet.jpg"
    sheet.save(sheet_path, quality=90)
    print(f"contact sheet: {sheet_path}")


if __name__ == "__main__":
    main()
