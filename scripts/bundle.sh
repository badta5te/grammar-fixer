#!/bin/bash
# Builds a .app out of what SwiftPM produced and signs it.
#
# The signature has to be stable: macOS ties granted Accessibility access to
# the pair of path and signature. With an ad-hoc signature the code hash changes
# from build to build, and access has to be granted again every time.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-debug}"
APP_NAME="GrammarFixer"
BUNDLE_ID="com.badta5te.GrammarFixer"
DEV_IDENTITY="GrammarFixer Dev"
APP="build/${APP_NAME}.app"

swift build -c "$CONFIG"
BINARY="$(swift build -c "$CONFIG" --show-bin-path)/${APP_NAME}"

rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "$BINARY" "${APP}/Contents/MacOS/${APP_NAME}"
cp Resources/Info.plist "${APP}/Contents/Info.plist"

# Order matters: the assembled bundle is signed as a whole, or the signature
# will not cover Info.plist.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    identity="$SIGN_IDENTITY"
# No -v on purpose: a fresh self-signed certificate counts as untrusted and
# would not be found with -v. Local signing needs no trust, and codesign works
# with it.
elif security find-identity -p codesigning 2>/dev/null | grep -qF "$DEV_IDENTITY"; then
    identity="$DEV_IDENTITY"
else
    identity="-"
    cat >&2 <<WARNING

  No «${DEV_IDENTITY}» certificate found, so the signature will be ad-hoc.
  Accessibility access will have to be granted again after every build.
  The README explains how to make the certificate once, under Signing.

WARNING
fi

# --force overwrites the signature and the debug entitlements SwiftPM puts on
# the executable while building.
codesign --force --sign "$identity" --identifier "$BUNDLE_ID" --timestamp=none "$APP"

echo "Built: ${APP}"
echo "Signed with: ${identity}"
