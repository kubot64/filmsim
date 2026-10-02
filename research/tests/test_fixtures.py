import json

import numpy as np

from filmsim import fixtures


def test_committed_fixtures_match_the_code():
    """research/tests/fixtures/transforms.json must be rewritten (`make fixtures`) when a transform changes."""
    committed = json.loads(fixtures.PATH.read_text())
    fresh = fixtures.build()
    assert committed["seed"] == fresh["seed"]
    assert list(committed["transforms"]) == list(fresh["transforms"])
    for name, cases in fresh["transforms"].items():
        old = committed["transforms"][name]
        assert len(old) == len(cases), name
        for key in ("in", "params", "out"):
            if key not in cases[0]:
                continue
            # Values may differ by a libm ulp between machines (macOS writes the file, CI runs
            # Linux). Outputs go through log10, pow and cos, and so do some inputs (log-uniform
            # samples, the hue circle). The Swift tests read the inputs from the file, so a
            # rounding difference there cannot hide a mismatch; 1e-12 is far below their tolerances.
            np.testing.assert_allclose(
                [c[key] for c in old], [c[key] for c in cases], rtol=0, atol=1e-12, err_msg=name
            )


def test_dumps_reads_back():
    data = fixtures.build()
    assert json.loads(fixtures.dumps(data)) == data
