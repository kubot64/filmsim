"""ColorChecker patches measured on a real scan of Portra 400VC, the target `negative.PORTRA_400VC`
is fitted to.

Source: the "Portra 400VC test" album by Flickr user tgray1 (flickr.com/photos/tgray1/albums/72157626009040382),
frame "400VC proper exposure": daylight, an X-Rite ColorChecker Passport and a Kodak Gray Scale
next to red and green objects. The 1600 px JPEG was sampled with an 11x11 px box inside each
patch, grey-balanced so the three middle greys (patches 20 to 22) average to neutral, and
converted to CIE Lab (sRGB, D65). The photos themselves are not in the repository.

The other frames of the album bracket the same scene from -4 to +5 stops, but the scanner
levelled each one: from -1 to +5 the greys come out almost the same, so they show the
negative's latitude, not its tone curve. From -3 down the blacks lift to about 0.17 and the
whites drop, the toe running out.

The scan is brighter than an 18 % mid-grey mapping: the fit puts it about +1.2 stops over.
"""

from __future__ import annotations

# Scan brightness relative to the pipeline's 18 % mid-grey, from the fit.
SCAN_EXPOSURE_EV = 1.17

# CIE Lab of the 24 patches, in the ColorChecker's order (dark skin ... black).
SCAN_LAB: tuple[tuple[float, float, float], ...] = (
    (55.3, 26.3, 29.4),  # dark skin
    (88.3, 8.3, 8.7),  # light skin
    (80.7, -7.2, -12.1),  # blue sky
    (59.3, -19.9, 34.1),  # foliage
    (84.7, 3.9, -9.4),  # blue flower
    (92.6, -18.0, 1.5),  # bluish green
    (76.5, 22.1, 54.7),  # orange
    (72.2, 0.9, -35.1),  # purplish blue
    (71.5, 43.9, 7.4),  # moderate red
    (48.6, 32.0, -24.0),  # purple
    (91.7, -31.2, 56.6),  # yellow green
    (87.7, -2.1, 67.7),  # orange yellow
    (56.9, 8.0, -53.3),  # blue
    (82.2, -57.2, 49.0),  # green
    (58.5, 65.2, 47.7),  # red
    (94.8, -14.4, 61.9),  # yellow
    (80.3, 30.2, -9.0),  # magenta
    (85.9, -31.6, -12.1),  # cyan
    (98.3, -0.4, 0.5),  # white 9.5
    (95.3, 0.8, -0.5),  # neutral 8
    (90.3, -1.0, 0.5),  # neutral 6.5
    (77.9, 0.1, 0.0),  # neutral 5
    (50.2, 1.1, -2.3),  # neutral 3.5
    (11.0, -7.5, 0.8),  # black 2
)
