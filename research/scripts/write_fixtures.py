"""Rewrite the transform fixtures the Swift tests compare against (filmsim/fixtures.py).

Example:
    uv run python scripts/write_fixtures.py
"""

from __future__ import annotations

from filmsim import fixtures


def main() -> None:
    fixtures.PATH.parent.mkdir(parents=True, exist_ok=True)
    fixtures.PATH.write_text(fixtures.dumps(fixtures.build()))
    print(f"wrote {fixtures.PATH}")


if __name__ == "__main__":
    main()
