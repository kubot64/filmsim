"""Bake a colour-negative look into a .cube that the app loads like the official LUTs.

Example:
    uv run python scripts/bake_negative.py --out ../ios/FilmSim/LUTs/Portra400VC_65grid.cube

The LUT takes F-Log2 / F-Gamut codes and returns sRGB codes (filmsim/negative.py).
"""

from __future__ import annotations

import argparse
from pathlib import Path

from filmsim import portra400vc
from filmsim.negative import PORTRA_400VC, bake_lut


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--size", type=int, default=65)
    args = ap.parse_args()
    lut = bake_lut(portra400vc, PORTRA_400VC, size=args.size, title="Portra 400VC (datasheet model)")
    lut.save(args.out)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
