"""Render a RAF through the pipeline and compare against the camera JPEG.

Example:
    uv run python scripts/compare_raf.py \
        --raf samples/DSCF0001.RAF --jpeg samples/DSCF0001.JPG \
        --lut luts/official/FLog2_to_PROVIA_65grid_V.1.00.cube --sweep-ev -2 2 0.25

The EV sweep is how the exposure anchor gets decided (docs/OPEN_QUESTIONS.md).
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from filmsim import CubeLUT, Recipe, render
from filmsim.metrics import delta_e_stats
from filmsim.rawio import crop_center, load_raw_linear, load_srgb, resize_linear, resize_to, save_srgb

# Compare at reduced size: ΔE is about colour, not sharpness. The linear image is
# shrunk before rendering, so each EV step renders ~1M pixels instead of ~40M.
COMPARE_WIDTH = 1200


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raf", required=True)
    ap.add_argument("--jpeg", required=True)
    ap.add_argument("--lut", required=True)
    ap.add_argument("--ev", type=float, default=0.0)
    ap.add_argument("--sweep-ev", nargs=3, type=float, metavar=("START", "STOP", "STEP"))
    ap.add_argument("--out", type=Path, help="directory for side-by-side PNGs")
    args = ap.parse_args()

    lut = CubeLUT.load(args.lut)
    ref = load_srgb(args.jpeg)
    h, w = ref.shape[:2]
    linear = crop_center(load_raw_linear(args.raf), h, w)
    size = (COMPARE_WIDTH, round(COMPARE_WIDTH * h / w))
    linear_small = resize_linear(linear, size)
    ref_small = resize_to(ref, size)

    evs = [args.ev]
    if args.sweep_ev:
        start, stop, step = args.sweep_ev
        evs = list(np.arange(start, stop + 1e-9, step))

    best = None
    for ev in evs:
        out_small = render(linear_small, Recipe(film_sim="lut", exposure_ev=ev), {"lut": lut})
        stats = delta_e_stats(out_small, ref_small)
        print(f"ev={ev:+.2f}  " + "  ".join(f"{k}={v:.2f}" for k, v in stats.items()))
        if best is None or stats["median"] < best[1]["median"]:
            best = (ev, stats, out_small)

    ev, stats, out_small = best
    print(f"\nbest ev={ev:+.2f} median ΔE={stats['median']:.2f}")
    if args.out:
        args.out.mkdir(parents=True, exist_ok=True)
        save_srgb(args.out / "render.png", out_small)
        save_srgb(args.out / "reference.png", ref_small)
        save_srgb(args.out / "side_by_side.png", np.concatenate([out_small, ref_small], axis=1))
        print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
