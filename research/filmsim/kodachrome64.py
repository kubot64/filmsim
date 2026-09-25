"""Kodachrome 64 curves traced from the vector art in Kodak E-88.

Source: Eastman Kodak Company, "KODACHROME 64 and 200 Films", Technical Data /
Color Reversal Film, June 2009, publication E-88. Only the KODACHROME 64 Film
section. Kodachrome 200 in the same PDF, and Kodachrome 64 Professional in
E-55, are different emulsions and are not included.

The PDF stores the graphs as vector paths. The plot frame matches the tick
marks, and these tables are samples of those paths. On the characteristic
plot the stroke is about 0.01 Status A wide, so the third decimal is the
trace of the line, not a tighter measurement. The dye strokes are about
0.003 wide.

Characteristic curves: daylight, 1/50 second, Process K-14, Status A
densitometry. ``LOG_EXPOSURE_LUX_SECONDS`` is log10 of exposure in
lux-seconds. The printed axis runs from -3 to +1; the three curves are
inked only from -2.4 to +0.4. Density falls as exposure rises (reversal).
R, G, and B were identified by which path the R/G/B labels sit on.

Spectral dye density: each curve is normalized to a visual density of 1.0
under a 3200 K viewing illuminant. Yellow, magenta, and cyan are each
scaled on their own, so they do not add up to ``neutral``.
"""

from __future__ import annotations

LOG_EXPOSURE_LUX_SECONDS: tuple[float, ...] = (
    -2.400, -2.300, -2.200, -2.100, -2.000, -1.900, -1.800, -1.700,
    -1.600, -1.500, -1.400, -1.300, -1.200, -1.100, -1.000, -0.900,
    -0.800, -0.700, -0.600, -0.500, -0.400, -0.300, -0.200, -0.100,
    0.000, 0.100, 0.200, 0.300, 0.400,
)

# Status A density at LOG_EXPOSURE_LUX_SECONDS.
STATUS_A: dict[str, tuple[float, ...]] = {
    "R": (
        3.680, 3.665, 3.638, 3.589, 3.518, 3.426, 3.313, 3.175,
        3.005, 2.800, 2.572, 2.331, 2.090, 1.861, 1.650, 1.453,
        1.269, 1.096, 0.935, 0.784, 0.649, 0.540, 0.453, 0.382,
        0.316, 0.255, 0.211, 0.189, 0.180,
    ),
    "G": (
        3.450, 3.433, 3.408, 3.368, 3.302, 3.208, 3.083, 2.925,
        2.740, 2.526, 2.300, 2.072, 1.852, 1.645, 1.453, 1.265,
        1.091, 0.934, 0.795, 0.673, 0.567, 0.477, 0.401, 0.338,
        0.288, 0.249, 0.221, 0.203, 0.190,
    ),
    "B": (
        3.330, 3.287, 3.238, 3.179, 3.104, 3.009, 2.886, 2.730,
        2.543, 2.332, 2.118, 1.907, 1.703, 1.507, 1.323, 1.159,
        1.009, 0.873, 0.750, 0.641, 0.546, 0.462, 0.392, 0.333,
        0.285, 0.249, 0.223, 0.208, 0.200,
    ),
}

WAVELENGTH_NM: tuple[int, ...] = (
    420, 430, 440, 450, 460, 470, 480, 490,
    500, 510, 520, 530, 540, 550, 560, 570,
    580, 590, 600, 610, 620, 630, 640, 650,
    660, 670, 680, 690, 700,
)

# Diffuse spectral density at WAVELENGTH_NM.
SPECTRAL_DENSITY: dict[str, tuple[float, ...]] = {
    "yellow": (
        0.640, 0.730, 0.769, 0.761, 0.709, 0.618, 0.481, 0.346,
        0.235, 0.150, 0.091, 0.052, 0.030, 0.017, 0.010, 0.005,
        0.002, 0.000, 0.000, 0.000, 0.001, 0.003, 0.004, 0.005,
        0.005, 0.005, 0.005, 0.005, 0.005,
    ),
    "magenta": (
        0.320, 0.282, 0.251, 0.232, 0.236, 0.286, 0.393, 0.519,
        0.659, 0.816, 0.952, 1.035, 1.063, 1.030, 0.940, 0.807,
        0.645, 0.485, 0.354, 0.253, 0.179, 0.130, 0.098, 0.077,
        0.062, 0.051, 0.040, 0.030, 0.020,
    ),
    "cyan": (
        0.150, 0.107, 0.071, 0.045, 0.029, 0.022, 0.019, 0.018,
        0.017, 0.018, 0.021, 0.028, 0.041, 0.065, 0.099, 0.147,
        0.215, 0.327, 0.497, 0.722, 0.965, 1.169, 1.263, 1.232,
        1.122, 0.972, 0.826, 0.697, 0.580,
    ),
    "neutral": (
        1.120, 1.110, 1.089, 1.047, 0.982, 0.923, 0.890, 0.891,
        0.925, 0.993, 1.068, 1.123, 1.141, 1.113, 1.044, 0.948,
        0.855, 0.819, 0.859, 0.997, 1.170, 1.308, 1.369, 1.320,
        1.191, 1.027, 0.873, 0.740, 0.620,
    ),
}
