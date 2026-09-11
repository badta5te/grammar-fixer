APP := build/GrammarFixer.app

# XCTest ships with Xcode, not with CommandLineTools. A full Xcode is not
# needed to build the app but is needed to run the tests, so when the current
# toolchain lacks it the targets use Xcode's toolchain through an environment
# variable. That needs no sudo and changes nothing system-wide, unlike
# xcode-select -s. One toolchain for every target is deliberate: otherwise the
# build and the tests would keep swapping each other's SDK and rebuild
# everything each time.
#
# The path to Xcode is not hard-coded: it may be renamed, live outside
# /Applications or come from xcodes. Ask Spotlight first and fall back to the
# default path only after.
ifeq ($(shell xcrun --find xctest 2>/dev/null),)
XCODE_APP := $(shell mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -1)
ifeq ($(XCODE_APP),)
XCODE_APP := $(wildcard /Applications/Xcode.app)
endif
ifneq ($(XCODE_APP),)
export DEVELOPER_DIR := $(XCODE_APP)/Contents/Developer
endif
endif

.PHONY: all run bundle release verify test clean

all: run

## Build, bundle, sign and launch.
# open reuses an instance that is already running, so wait for the old one to
# die first, or the old build launches instead of the new one.
run: bundle
	@pkill -x GrammarFixer 2>/dev/null || true
	@while pgrep -qx GrammarFixer; do sleep 0.1; done
	@open $(APP)
	@echo "Launched, look for the menu bar icon"

## Build and sign the bundle
bundle:
	@./scripts/bundle.sh

## The same, built in the release configuration
release:
	@CONFIG=release ./scripts/bundle.sh

## Show what the bundle is signed with and what entitlements it has
verify:
	@codesign -dvvv $(APP) 2>&1 | grep -E '^(Identifier|Authority|Signature)' || true
	@echo "--- entitlements:"
	@codesign -d --entitlements - --xml $(APP) 2>/dev/null | plutil -p - 2>/dev/null || echo "no entitlements"
	@echo "--- LSUIElement:"
	@plutil -extract LSUIElement raw $(APP)/Contents/Info.plist

test:
	@xcrun --find xctest >/dev/null 2>&1 || { \
		echo "Running the tests needs Xcode: XCTest is not part of the Command Line Tools" >&2; \
		exit 1; }
	@swift test

clean:
	@rm -rf build .build
