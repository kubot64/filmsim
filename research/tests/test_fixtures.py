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
            # Inputs come from a seeded generator and match exactly. Outputs may differ by a
            # libm ulp between machines (log10, pow, cos), far below the Swift tolerances.
            atol = 0 if key == "in" else 1e-12
            np.testing.assert_allclose(
                [c[key] for c in old], [c[key] for c in cases], rtol=0, atol=atol, err_msg=name
            )


def test_dumps_reads_back():
    data = fixtures.build()
    assert json.loads(fixtures.dumps(data)) == data
