export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: test test-py test-swift xcode ci luts

test: test-py test-swift

test-py:
	cd research && uv run pytest -q -rs

test-swift:
	cd ios/FilmSimCore && swift test

xcode:
	cd ios && xcodegen generate

luts:
	bash scripts/fetch_luts.sh

# Local full check. GitHub Actions runs the same steps as parallel jobs in
# .github/workflows/ci.yml (python / swift-package / ios-app) so macOS runners
# are not blocked on the Linux Python job.
ci: luts
	cd research && uv sync --locked && uv run pytest -q -rs
	cd ios/FilmSimCore && swift test
	cd ios && xcodegen generate && xcodebuild -project FilmSim.xcodeproj -scheme FilmSim -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet
