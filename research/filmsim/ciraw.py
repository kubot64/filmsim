"""Linearise a RAW file with Apple's CIRAWFilter, the engine the iOS app uses.

The work happens in scripts/ci_linear.swift (same filter settings as
RawDeveloper.developLinear, orientation kept, no 35mm crop), compiled into
out/bin on first use. macOS only.
"""

from __future__ import annotations

import json
import subprocess
import tempfile
from pathlib import Path

import numpy as np

RESEARCH = Path(__file__).resolve().parent.parent
HELPER_SRC = RESEARCH / "scripts" / "ci_linear.swift"
HELPER_BIN = RESEARCH / "out" / "bin" / "ci_linear"


def _helper() -> Path:
    if not HELPER_BIN.exists() or HELPER_BIN.stat().st_mtime < HELPER_SRC.stat().st_mtime:
        HELPER_BIN.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["swiftc", "-O", "-o", str(HELPER_BIN), str(HELPER_SRC)], check=True)
    return HELPER_BIN


def load_raw_linear_ciraw(path: str | Path) -> tuple[np.ndarray, dict]:
    """Upright scene-linear Display P3 float32 image from CIRAWFilter, plus size and EXIF.

    Unlike LibRaw, CIRAWFilter applies the lens-shading gain maps and the file's
    baseline exposure, and keeps values above 1.0.
    """
    with tempfile.NamedTemporaryFile(suffix=".f32") as tmp:
        out = subprocess.run([str(_helper()), str(path), tmp.name], check=True, capture_output=True, text=True)
        info = json.loads(out.stdout)
        img = np.fromfile(tmp.name, dtype=np.float32).reshape(info["height"], info["width"], 3)
    return img, info
