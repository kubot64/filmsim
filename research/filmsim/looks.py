"""Which film-simulation keys get which post-LUT fixes.

Keys come from `film_sim_key` (official Fujifilm LUT file names) or from the app's
named looks. Keep in sync with `FilmSimulation.usesXSeriesShoulder` /
`FilmSimulation.usesWarmHue` in FilmSimCore.
"""

from __future__ import annotations

from pathlib import Path

# Official Fujifilm LUTs only. The X-series highlight shoulder (#16) pulls GFX LUTs
# toward X-series JPEGs; a look fitted to another camera already has that camera's
# highlights in the LUT.
FUJIFILM_FILM_SIMS = ("provia", "classic_chrome", "lut")

# Provia only (#11). Classic Chrome's warm error is smaller, and a Provia-fitted
# rotation made some Classic Chrome pairs worse.
WARM_HUE_FILM_SIMS = ("provia",)


def film_sim_key(path: str | Path) -> str:
    """Recipe.film_sim for an official LUT file, so render() applies per-simulation fixes.

    Other official files (named "FLog2_to_...") map to "lut", which gets only the fixes
    every Fujifilm LUT gets. Anything else, such as a LUT from scripts/fit_look.py, maps
    to "fitted" and gets none of them.
    """
    name = Path(path).name.upper()
    if not name.startswith("FLOG2_TO_"):
        return "fitted"
    if "PROVIA" in name:
        return "provia"
    if "CLASSIC-CHROME" in name:
        return "classic_chrome"
    return "lut"
