"""Seeded random inputs and their outputs for the per-pixel transforms both sides implement.

The Swift package reads the committed JSON (research/tests/fixtures/transforms.json) and runs
the same inputs through its CPU functions and the Metal kernels, so the Swift copies are held
to this code over the whole input range instead of a few hand-copied points (docs/adr/0009).
Rewrite it with `make fixtures`; tests/test_fixtures.py fails while it is stale.

Inputs are draws from the Generator or literals. Do not pass those draws through powers or
trigonometry: libm differs by a ulp across machines, and `make fixtures` would rewrite this
file even though the transforms did not change.

Each transform is a list of cases {"in": [...], "params": [...], "out": [...]}. "params" is
only present when the transform takes parameters (tone curve: highlight, shadow).
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from .flog2 import FLOG2
from .gamut import BT709, F_GAMUT, P3_D65, apply_matrix, conversion_matrix
from .grain import grain_weight
from .hue import x_series_warm_hue
from .tone import tone_curve, x_series_shoulder

PATH = Path(__file__).parents[1] / "tests/fixtures/transforms.json"
SEED = 97

# Highlight and shadow as the develop screen offers them (DevelopView: -2...4, step 1).
TONE_RANGE = (-2.0, 4.0)


def _cases(inputs: np.ndarray, outputs: np.ndarray, params: np.ndarray | None = None) -> list:
    cases = []
    for i in range(len(inputs)):
        case = {"in": np.atleast_1d(inputs[i]).tolist()}
        if params is not None:
            case["params"] = np.atleast_1d(params[i]).tolist()
        case["out"] = np.atleast_1d(outputs[i]).tolist()
        cases.append(case)
    return cases


def _tone_params(rng: np.random.Generator, n: int) -> np.ndarray:
    """Each of highlight / shadow is, a third each: 0 (that branch off), an app step, or anywhere in range."""

    def parameter() -> np.ndarray:
        kind = rng.integers(0, 3, n)
        steps = rng.integers(-2, 5, n).astype(np.float64)
        anywhere = rng.uniform(*TONE_RANGE, n)
        return np.where(kind == 0, 0.0, np.where(kind == 1, steps, anywhere))

    return np.stack([parameter(), parameter()], axis=-1)


def build() -> dict:
    """All fixtures, from SEED. Same inputs every run; outputs follow the current code."""
    rng = np.random.default_rng(SEED)
    transforms: dict[str, list] = {}

    # Scene-linear 0...16, and the same count drawn uniformly below cut1 (the toe).
    x = np.concatenate(
        [
            [0.0, FLOG2.cut1, np.nextafter(FLOG2.cut1, 0), 0.0005, 0.01, 0.18, 0.5, 0.9, 1.0, 4.0],
            [16.0],
            rng.uniform(0, 16, 150),
            rng.uniform(0, FLOG2.cut1, 150),
        ]
    )
    transforms["flog2_encode"] = _cases(x, FLOG2.encode(x))

    y = np.concatenate(
        [[0.0, FLOG2.f, FLOG2.cut2, np.nextafter(FLOG2.cut2, 0), 1.0], rng.uniform(0, 1, 300)]
    )
    transforms["flog2_decode"] = _cases(y, FLOG2.decode(y))

    for name, src, dst in [
        ("gamut_p3_to_fgamut", P3_D65, F_GAMUT),
        ("gamut_fgamut_to_p3", F_GAMUT, P3_D65),
        ("gamut_bt709_to_fgamut", BT709, F_GAMUT),
        ("gamut_fgamut_to_bt709", F_GAMUT, BT709),
    ]:
        rgb = np.concatenate([np.eye(3), np.ones((1, 3)), rng.uniform(0, 1, (200, 3))])
        transforms[name] = _cases(rgb, apply_matrix(rgb, conversion_matrix(src, dst)))

    # Half anywhere, half bright enough to reach the shoulder above the knee.
    greys = np.repeat(np.array([0.0, 0.45, 0.6, 0.7, 0.8, 0.9, 0.95, 1.0])[:, None], 3, axis=1)
    rgb = np.concatenate([greys, rng.uniform(0, 1, (150, 3)), rng.uniform(0.5, 1, (150, 3))])
    transforms["highlight_shoulder"] = _cases(rgb, x_series_shoulder(rgb))

    golden = np.array([[0.8, 0.2, 0.1], [0.9, 0.55, 0.2], [0.7, 0.7, 0.2], [0.2, 0.4, 0.9]])
    # Window edges (center ± width = 60° and 220°) and the hue wrap (0° and 355°), at Y' 0.5
    # and two chroma levels. RGB literals: a hue circle goes through cos/sin.
    marks = np.array(
        [
            [0.6363816805879734, 0.4500930351048614, 0.5927800000000001],  # 60°, chroma 0.1
            [0.8409542014699335, 0.3752325877621535, 0.7319500000000001],  # 60°, chroma 0.25
            [0.3987738072265638, 0.5444403200773168, 0.3578527931348424],  # 220°, chroma 0.1
            [0.24693451806640948, 0.6111008001932918, 0.1446319828371061],  # 220°, chroma 0.25
            [0.5, 0.48126757270693515, 0.68556],  # 0°, chroma 0.1
            [0.5, 0.45316893176733786, 0.9639],  # 0°, chroma 0.25
            [0.4862747136320988, 0.48541882711880746, 0.6848538881779043],  # 355°, chroma 0.1
            [0.46568678408024694, 0.4635470677970187, 0.9621347204447608],  # 355°, chroma 0.25
        ]
    )
    rgb = np.concatenate([golden, [[0.5, 0.5, 0.5]], marks, rng.uniform(0, 1, (200, 3))])
    transforms["warm_hue"] = _cases(rgb, x_series_warm_hue(rgb))

    golden_x = np.array([0.75, 0.25, 0.75, 0.25, 0.8])
    golden_p = np.array([[4, 0], [0, 4], [-2, 0], [0, -2], [2, 3]], dtype=np.float64)
    x = np.concatenate([[0.0, 0.5, 1.0], golden_x, rng.uniform(0, 1, 300)])
    params = np.concatenate([[[4, 4], [4, 4], [4, 4]], golden_p, _tone_params(rng, 300)])
    # tone_curve takes one highlight / shadow per call.
    tone = np.array([tone_curve(np.array([xi]), *p)[0] for xi, p in zip(x, params, strict=True)])
    transforms["tone_curve"] = _cases(x, tone, params)

    lum = np.concatenate([[0.0, 0.02, 0.25, 0.4, 0.98, 1.0], rng.uniform(0, 1, 200)])
    transforms["grain_weight"] = _cases(lum, grain_weight(lum))

    return {"seed": SEED, "transforms": transforms}


def dumps(fixtures: dict) -> str:
    """One case per line, so a changed constant shows up as a readable diff."""
    lines = ["{", f'  "seed": {fixtures["seed"]},', '  "transforms": {']
    names = list(fixtures["transforms"])
    for i, name in enumerate(names):
        cases = fixtures["transforms"][name]
        lines.append(f'    "{name}": [')
        lines += [
            f"      {json.dumps(c)}{',' if j < len(cases) - 1 else ''}" for j, c in enumerate(cases)
        ]
        lines.append(f"    ]{',' if i < len(names) - 1 else ''}")
    lines += ["  }", "}", ""]
    return "\n".join(lines)
