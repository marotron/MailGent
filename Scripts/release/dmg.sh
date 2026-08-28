#!/usr/bin/env bash
# Build a Release MailGent.app and wrap it in a compressed DMG for GitHub Releases.
#
# Optional (set when Developer ID + notary profile exist):
#   MAILGENT_SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   MAILGENT_NOTARY_PROFILE  keychain profile for `xcrun notarytool`
#   RELEASE_TAG              e.g. v0.1.6 — must match MARKETING_VERSION in project.yml
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SCHEME=MailGent
PROJECT=MailGent.xcodeproj
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"
DERIVED_DATA="${DERIVED_DATA:-.build/DerivedData}"
CONFIG=Release
APP_NAME=MailGent

VERSION="$(
  sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)".*/\1/p' project.yml | head -1
)"
if [[ -z "$VERSION" ]]; then
  echo "error: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

if [[ -n "${RELEASE_TAG:-}" ]]; then
  EXPECTED="${RELEASE_TAG#v}"
  if [[ "$EXPECTED" != "$VERSION" ]]; then
    echo "error: tag ${RELEASE_TAG} (v${EXPECTED}) != MARKETING_VERSION ${VERSION} in project.yml" >&2
    exit 1
  fi
fi

DIST_DIR="$ROOT/dist"
STAGE_DIR="$DIST_DIR/stage"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

echo "→ MailGent ${VERSION} (${CONFIG}, ${DESTINATION})"

xcodegen generate

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES \
  build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIG/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: ${APP_PATH} not found after build" >&2
  exit 1
fi

if [[ -n "${MAILGENT_SIGN_IDENTITY:-}" ]]; then
  echo "→ codesign (${MAILGENT_SIGN_IDENTITY})"
  codesign --force --deep --options runtime --sign "$MAILGENT_SIGN_IDENTITY" "$APP_PATH"
  codesign --verify --deep --strict "$APP_PATH"
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

rm -f "$DMG_PATH"
echo "→ hdiutil create ${DMG_PATH}"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ -n "${MAILGENT_NOTARY_PROFILE:-}" ]]; then
  echo "→ notarize (${MAILGENT_NOTARY_PROFILE})"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$MAILGENT_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

rm -rf "$STAGE_DIR"

echo ""
echo "Created: ${DMG_PATH}"
echo "SHA256:  $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [[ -z "${MAILGENT_SIGN_IDENTITY:-}" ]]; then
  echo ""
  echo "Note: unsigned/ad-hoc build. Set MAILGENT_SIGN_IDENTITY + MAILGENT_NOTARY_PROFILE for Gatekeeper-safe distribution."
fi
