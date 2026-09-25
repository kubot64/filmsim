export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

.PHONY: test test-py test-swift xcode

test: test-py test-swift

test-py:
	cd research && uv run pytest -q

test-swift:
	cd ios/FilmSimCore && swift test

xcode:
	cd ios && xcodegen generate
