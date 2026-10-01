export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: test test-py test-swift lint lint-py lint-swift fmt xcode ci luts

test: test-py test-swift

test-py:
	cd research && uv run pytest -q -rs

test-swift:
	cd ios/FilmSimCore && swift test

lint: lint-py lint-swift

lint-py:
	cd research && uv run ruff check . && uv run ruff format --check .

# `swift format` ships with the Xcode 16 toolchain; .swift-format at the root holds the settings.
lint-swift:
	swift format lint --strict --recursive --parallel ios

fmt:
	cd research && uv run ruff check --fix . && uv run ruff format .
	swift format --in-place --recursive --parallel ios

xcode:
	cd ios && xcodegen generate

luts:
	bash scripts/fetch_luts.sh

# Local full check. GitHub Actions runs the same steps as parallel jobs in
# .github/workflows/ci.yml (python / swift-package / ios-app) so macOS runners
# are not blocked on the Linux Python job.
ci: luts
	cd research && uv sync --locked && uv run ruff check . && uv run ruff format --check . && uv run pytest -q -rs
	swift format lint --strict --recursive --parallel ios
	cd ios/FilmSimCore && swift test
	cd ios && xcodegen generate && xcodebuild -project FilmSim.xcodeproj -scheme FilmSim -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet
