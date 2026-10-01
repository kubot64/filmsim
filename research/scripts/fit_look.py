"""Fit a look LUT from RAW + camera JPEG pairs, for looks with no official LUT (e.g. Leica Standard).

Example:
    uv run python scripts/fit_look.py samples/leica/*.DNG \
        --title "Leica Standard" --out luts/fitted/Leica_Standard.cube

Each RAW needs the camera JPEG of the same shot next to it (same stem, .JPG/.jpg).
The RAW goes through the same front half as the app (linear -> F-Log2), so the LUT
takes F-Log2 codes like the official ones and slots into the same pipeline.

Before the final fit, each pair is left out once: the LUT is fitted on the others and
compared with the left-out JPEG. That ΔE is what to expect on a new photo; the ΔE on
the fitted pairs themselves would be optimistic.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

from filmsim import FLOG2, CubeLUT
from filmsim.lutfit import bin_pairs, fit_lut
from filmsim.metrics import delta_e_stats
from filmsim.rawio import crop_center, load_raw_linear, load_srgb, resize_linear, resize_to

# Colour, not sharpness: pairs are compared and fitted at this width.
FIT_WIDTH = 800
# Only the centre is used. Camera JPEGs usually have lens distortion corrected and LibRaw
# does not, so the corners do not line up pixel for pixel.
CENTER_FRACTION = 0.8
# JPEG values this close to 0 or 1 are clipped: they say nothing about the look.
CLIP_MARGIN = 2 / 255


def find_jpeg(raw: Path) -> Path:
    for ext in (".JPG", ".jpg", ".JPEG", ".jpeg"):
        p = raw.with_suffix(ext)
        if p.exists():
            return p
    raise FileNotFoundError(f"no JPEG next to {raw}")


def crop_to_aspect(img: np.ndarray, aspect: float) -> np.ndarray:
    """Centre crop to width/height `aspect`."""
    h, w = img.shape[:2]
    if w / h > aspect:
        return crop_center(img, h, round(h * aspect))
    return crop_center(img, round(w / aspect), w)


def load_pair(raw: Path, ev: float) -> tuple[np.ndarray, np.ndarray]:
    """(F-Log2 codes, JPEG codes), each (N, 3), for the usable pixels of one shot."""
    ref = load_srgb(find_jpeg(raw))
    h, w = ref.shape[:2]
    linear = crop_to_aspect(load_raw_linear(raw), w / h)
    size = (FIT_WIDTH, round(FIT_WIDTH * h / w))
    lin = resize_linear(linear, size)
    ref = resize_to(ref, size)
    ch, cw = round(size[1] * CENTER_FRACTION), round(size[0] * CENTER_FRACTION)
    lin, ref = crop_center(lin, ch, cw), crop_center(ref, ch, cw)

    log = np.clip(FLOG2.encode(np.clip(lin * 2.0**ev, 0.0, None)), 0.0, 1.0).reshape(-1, 3)
    out = ref.reshape(-1, 3)
    usable = (out.min(axis=1) > CLIP_MARGIN) & (out.max(axis=1) < 1 - CLIP_MARGIN)
    return log[usable], out[usable]


def fit(
    pairs: list[tuple[np.ndarray, np.ndarray]],
    size: int,
    smoothness: float,
    prior: CubeLUT | None,
    title: str,
) -> CubeLUT:
    x = np.concatenate([p[0] for p in pairs])
    y = np.concatenate([p[1] for p in pairs])
    xb, yb, counts = bin_pairs(x, y)
    return fit_lut(
        xb, yb, size=size, smoothness=smoothness, prior=prior, weights=counts, title=title
    )


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("raws", nargs="+", type=Path)
    ap.add_argument("--out", type=Path, required=True, help=".cube to write, on the fit grid")
    ap.add_argument("--title", default="fitted look")
    ap.add_argument(
        "--ev", type=float, default=0.0, help="exposure before F-Log2, same for every pair"
    )
    ap.add_argument(
        "--size",
        type=int,
        default=33,
        help="LUT grid (33 is about 1 MB; 65 would be 8 MB and no better)",
    )
    ap.add_argument("--smoothness", type=float, default=1e-3)
    ap.add_argument(
        "--prior", type=Path, help="LUT the fit falls back to where the photos say nothing"
    )
    args = ap.parse_args()

    prior = CubeLUT.load(args.prior) if args.prior else None
    pairs = []
    for raw in args.raws:
        x, y = load_pair(raw, args.ev)
        print(f"{raw.name}: {x.shape[0]} usable pixels")
        pairs.append((x, y))

    if len(pairs) > 1:
        print("\nleft-out ΔE (fitted on the other pairs)")
        medians = []
        for i, raw in enumerate(args.raws):
            lut = fit(pairs[:i] + pairs[i + 1 :], args.size, args.smoothness, prior, args.title)
            x, y = pairs[i]
            stats = delta_e_stats(lut.apply(x)[:, None], y[:, None])
            medians.append(stats["median"])
            print(f"  {raw.name:24s} median={stats['median']:.2f}  p95={stats['p95']:.2f}")
        print(f"  median of medians {np.median(medians):.2f}")

    lut = fit(pairs, args.size, args.smoothness, prior, args.title)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    lut.save(args.out)
    print(f"\nwrote {args.out}")


if __name__ == "__main__":
    main()
