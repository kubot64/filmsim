"""Kodak Professional Portra 400VC curves traced from the vector art in the Kodak datasheet.

Source: Eastman Kodak Company, "KODAK PROFESSIONAL PORTRA 160NC, 160VC, 400NC, 400VC
and 800 Films", Japanese edition of TSC 0597-2, 2006, page 11 (the 400VC page).
Downloaded from https://www.kodakalaris.co.jp/images/portra800.pdf. 400VC ("vivid
colour") was replaced by Portra 400 (E-4050, 2010), a different emulsion that is not
included.

The PDF stores the graphs as vector paths inside clipping groups. Each axis was mapped
from its own tick marks, and these tables are samples of those paths. The traced
paths were overlaid on a 300 dpi render of the page to check the R/G/B and layer
assignments. The strokes are about 1 pt wide, which is 0.02 density on the
characteristic plot, so the third decimal is the trace of the line, not a tighter
measurement.

Characteristic curves: daylight exposure, Process C-41, Status M densitometry.
``LOG_EXPOSURE_LUX_SECONDS`` is log10 of exposure in lux-seconds; the curves are
inked from -3.44 to +0.56. ``LOG_H_REF`` is the exposure the sheet marks as the
reference (a normally exposed mid-grey). Negative film: density rises with exposure.
R, G and B were identified by the labels at the toe (B is the top curve).

Spectral dye density: diffuse density of the processed film for a mid-scale neutral
exposure, and of D-min (unexposed, the orange mask plus base). These are the sums of
all three dyes, not the dyes one by one.

Spectral sensitivity: log10 of relative sensitivity (reciprocal of the exposure in
erg/cm² that gives density 0.2 above D-min), daylight, 1/50 s. Named by the dye each
layer forms. The magenta-forming layer also has a lobe of about 1.3 to 1.5 in the
blue (390 to 470 nm); it is drawn that way on the sheet.
"""

from __future__ import annotations

LOG_H_REF = -1.44

# Rows follow the datasheet tables.
# fmt: off
LOG_EXPOSURE_LUX_SECONDS: tuple[float, ...] = (
    -3.4, -3.3, -3.2, -3.1, -3.0, -2.9, -2.8, -2.7,
    -2.6, -2.5, -2.4, -2.3, -2.2, -2.1, -2.0, -1.9,
    -1.8, -1.7, -1.6, -1.5, -1.4, -1.3, -1.2, -1.1,
    -1.0, -0.9, -0.8, -0.7, -0.6, -0.5, -0.4, -0.3,
    -0.2, -0.1, 0.0, 0.1, 0.2, 0.3, 0.4, 0.5,
)

# Status M density at LOG_EXPOSURE_LUX_SECONDS.
STATUS_M: dict[str, tuple[float, ...]] = {
    "R": (
        0.221, 0.224, 0.227, 0.229, 0.233, 0.238, 0.249, 0.268,
        0.298, 0.341, 0.390, 0.445, 0.500, 0.554, 0.608, 0.662,
        0.717, 0.772, 0.828, 0.884, 0.940, 0.997, 1.055, 1.112,
        1.170, 1.228, 1.286, 1.345, 1.405, 1.464, 1.524, 1.584,
        1.644, 1.704, 1.765, 1.826, 1.887, 1.948, 2.009, 2.072,
    ),
    "G": (
        0.647, 0.648, 0.651, 0.654, 0.659, 0.665, 0.679, 0.701,
        0.734, 0.778, 0.830, 0.889, 0.948, 1.006, 1.065, 1.123,
        1.182, 1.240, 1.298, 1.355, 1.413, 1.472, 1.530, 1.588,
        1.645, 1.703, 1.761, 1.818, 1.876, 1.933, 1.991, 2.049,
        2.106, 2.163, 2.220, 2.276, 2.333, 2.390, 2.447, 2.504,
    ),
    "B": (
        0.868, 0.871, 0.874, 0.877, 0.888, 0.908, 0.939, 0.984,
        1.039, 1.099, 1.165, 1.231, 1.297, 1.362, 1.428, 1.494,
        1.561, 1.627, 1.694, 1.760, 1.827, 1.893, 1.960, 2.027,
        2.094, 2.162, 2.229, 2.296, 2.363, 2.430, 2.498, 2.566,
        2.635, 2.703, 2.771, 2.839, 2.907, 2.975, 3.043, 3.113,
    ),
}

DYE_WAVELENGTH_NM: tuple[int, ...] = (
    400, 410, 420, 430, 440, 450, 460, 470,
    480, 490, 500, 510, 520, 530, 540, 550,
    560, 570, 580, 590, 600, 610, 620, 630,
    640, 650, 660, 670, 680, 690, 700,
)

# Diffuse spectral density at DYE_WAVELENGTH_NM.
DYE_DENSITY: dict[str, tuple[float, ...]] = {
    "midscale_neutral": (
        1.582, 1.354, 1.391, 1.528, 1.684, 1.806, 1.854, 1.858,
        1.823, 1.766, 1.665, 1.558, 1.462, 1.422, 1.443, 1.454,
        1.456, 1.448, 1.455, 1.426, 1.345, 1.215, 1.047, 0.882,
        0.756, 0.686, 0.671, 0.691, 0.732, 0.789, 0.850,
    ),
    "d_min": (
        1.127, 0.813, 0.758, 0.792, 0.844, 0.870, 0.865, 0.848,
        0.821, 0.791, 0.762, 0.733, 0.703, 0.693, 0.711, 0.710,
        0.662, 0.625, 0.609, 0.598, 0.595, 0.575, 0.514, 0.421,
        0.323, 0.250, 0.210, 0.191, 0.183, 0.182, 0.184,
    ),
}

# log10 relative sensitivity, sampled every 10 nm where the curve is drawn.
LOG_SENSITIVITY: dict[str, dict[int, float]] = {
    "yellow_forming": {
        380: 1.76, 390: 2.28, 400: 2.56, 410: 2.57, 420: 2.50, 430: 2.52,
        440: 2.53, 450: 2.45, 460: 2.52, 470: 2.58, 480: 2.04, 490: 1.42,
        500: 0.97, 510: 0.51,
    },
    "magenta_forming": {
        390: 1.36, 400: 1.55, 410: 1.50, 420: 1.40, 430: 1.34, 440: 1.26,
        450: 1.26, 460: 1.31, 470: 1.32, 480: 1.65, 490: 1.88, 500: 2.02,
        510: 2.07, 520: 2.19, 530: 2.31, 540: 2.40, 550: 2.43, 560: 2.35,
        570: 2.18, 580: 1.71, 590: 0.84,
    },
    "cyan_forming": {
        490: 0.47, 500: 0.62, 510: 0.75, 520: 0.87, 530: 0.87, 540: 0.85,
        550: 1.04, 560: 1.24, 570: 1.46, 580: 1.95, 590: 2.18, 600: 2.31,
        610: 2.44, 620: 2.48, 630: 2.46, 640: 2.19, 650: 1.45, 660: 0.63,
    },
}
# fmt: on
