"""Render a single RAW (RAF or DNG) with a recipe to PNG.

Example:
    uv run python scripts/render.py --raw IMG_0001.DNG \
        --lut luts/official/FLog2_to_CLASSIC-CHROME_65grid_V.1.00.cube \
        --ev 0.5 --wb 2 -4 --highlight -1 --shadow 1 --grain weak --out out/IMG_0001.png
"""

from __future__ import annotations

import argparse
from pathlib import Path

from filmsim import CubeLUT, Recipe, render
from filmsim.cube import film_sim_key
from filmsim.rawio import load_raw_linear, save_srgb


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", required=True)
    ap.add_argument("--lut", required=True)
    ap.add_argument("--ev", type=float, default=0.0)
    ap.add_argument("--wb", nargs=2, type=float, default=(0, 0), metavar=("R", "B"))
    ap.add_argument("--highlight", type=float, default=0.0)
    ap.add_argument("--shadow", type=float, default=0.0)
    ap.add_argument("--grain", default="off", choices=["off", "weak", "strong"])
    ap.add_argument("--grain-size", default="small", choices=["small", "large"])
    ap.add_argument("--out", type=Path, required=True)
    args = ap.parse_args()

    recipe = Recipe(
        film_sim=film_sim_key(args.lut),
        exposure_ev=args.ev,
        wb_shift=tuple(args.wb),
        highlight=args.highlight,
        shadow=args.shadow,
        grain_strength=args.grain,
        grain_size=args.grain_size,
    )
    out = render(load_raw_linear(args.raw), recipe, {recipe.film_sim: CubeLUT.load(args.lut)})
    args.out.parent.mkdir(parents=True, exist_ok=True)
    save_srgb(args.out, out)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
