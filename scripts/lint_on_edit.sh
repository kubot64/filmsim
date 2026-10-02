#!/usr/bin/env bash
# Claude Code PostToolUse hook: format the file Claude just edited, then lint it.
# Lint findings that the formatter cannot fix go back to Claude (exit 2) so it fixes them
# before CI does. Uses the same tools and settings as `make fmt` / `make lint`.
# Missing tools (no jq, uv or swift on this machine) skip silently; CI still checks.
set -uo pipefail

command -v jq >/dev/null || exit 0
file=$(jq -r '.tool_input.file_path // empty')
[ -n "$file" ] && [ -f "$file" ] || exit 0

root="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
case "$file" in
    "$root"/*) rel="${file#"$root"/}" ;;
    *) exit 0 ;;
esac

case "$rel" in
    */.build/* | */.venv/* | *.generated.swift) exit 0 ;;
    research/*.py)
        command -v uv >/dev/null || exit 0
        cd "$root/research" || exit 0
        uv run --quiet ruff check --fix --quiet "$file" >/dev/null 2>&1
        uv run --quiet ruff format --quiet "$file" >/dev/null 2>&1
        # Same two checks as `make lint-py`, so a file the formatter could not rewrite still comes back.
        out=$(uv run --quiet ruff check --quiet "$file" 2>&1 && uv run --quiet ruff format --check --quiet "$file" 2>&1) || {
            printf 'ruff found problems in %s:\n%s\n' "$rel" "$out" >&2
            exit 2
        }
        ;;
    ios/*.swift)
        if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
            export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
        fi
        swift format --version >/dev/null 2>&1 || exit 0
        swift format --in-place "$file" >/dev/null 2>&1
        out=$(swift format lint --strict "$file" 2>&1) || {
            printf 'swift format lint found problems in %s:\n%s\n' "$rel" "$out" >&2
            exit 2
        }
        ;;
esac
exit 0
