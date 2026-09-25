export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: test test-py test-swift xcode

test: test-py test-swift

test-py:
	cd research && uv run pytest -q

test-swift:
	cd ios/FilmSimCore && swift test

xcode:
	cd ios && xcodegen generate

.PHONY: ci luts
luts:
	bash scripts/fetch_luts.sh

ci: luts
	cd research && uv sync --locked && uv run pytest -q -rs
	cd ios/FilmSimCore && swift test
	cd ios && xcodegen generate && xcodebuild -project FilmSim.xcodeproj -scheme FilmSim -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO build -quiet
