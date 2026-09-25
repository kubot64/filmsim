"""filmsim research package.

Pipeline: linear scene-referred RGB -> WB shift -> exposure anchor -> F-Gamut
-> F-Log2 -> official Fujifilm LUT -> tone -> grain -> BT.709 code values.
"""

from .flog2 import FLOG, FLOG2, LogCurve
from .gamut import BT2020, BT709, F_GAMUT, P3_D65, conversion_matrix
from .cube import CubeLUT
from .pipeline import Recipe, render

__all__ = [
    "FLOG", "FLOG2", "LogCurve",
    "BT2020", "BT709", "F_GAMUT", "P3_D65", "conversion_matrix",
    "CubeLUT", "Recipe", "render",
]
