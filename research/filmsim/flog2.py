"""F-Log and F-Log2 transfer functions.

Constants are taken verbatim from the Fujifilm data sheets:
- F-Log2 Data Sheet Ver.1.1  https://dl.fujifilm-x.com/technical-data/F-Log2_DataSheet_E_Ver.1.1.pdf
- F-Log  Data Sheet Ver.1.2  https://dl.fujifilm-x.com/technical-data/F-Log_DataSheet_E_Ver.1.2.pdf

Reference points (F-Log2): 0% -> 0.093 (10bit 95), 18% -> 0.391 (400), 90% -> 0.557 (570).
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


@dataclass(frozen=True)
class LogCurve:
    a: float
    b: float
    c: float
    d: float
    e: float
    f: float
    cut1: float
    cut2: float

    def encode(self, x: np.ndarray | float) -> np.ndarray:
        """Scene-linear reflection (0.18 = 18% grey) -> log code value in [0, 1]."""
        x = np.asarray(x, dtype=np.float64)
        safe = np.maximum(self.a * x + self.b, 1e-12)
        log_part = self.c * np.log10(safe) + self.d
        lin_part = self.e * x + self.f
        return np.where(x >= self.cut1, log_part, lin_part)

    def decode(self, y: np.ndarray | float) -> np.ndarray:
        """Log code value in [0, 1] -> scene-linear reflection."""
        y = np.asarray(y, dtype=np.float64)
        log_part = (np.power(10.0, (y - self.d) / self.c)) / self.a - self.b / self.a
        lin_part = (y - self.f) / self.e
        return np.where(y >= self.cut2, log_part, lin_part)


FLOG2 = LogCurve(
    a=5.555556, b=0.064829, c=0.245281, d=0.384316,
    e=8.799461, f=0.092864,
    cut1=0.000889, cut2=0.100686685370811,
)

FLOG = LogCurve(
    a=0.555556, b=0.009468, c=0.344676, d=0.790453,
    e=8.735631, f=0.092864,
    cut1=0.00089, cut2=0.100537775223865,
)
