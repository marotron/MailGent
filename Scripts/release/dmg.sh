#!/usr/bin/env bash
# Build a Release MailGent.app and wrap it in a compressed DMG for GitHub Releases.
#
# Optional (set when Developer ID + notary profile exist):
#   MAILGENT_SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   MAILGENT_NOTARY_PROFILE  keychain profile for `xcrun notarytool`
#   RELEASE_TAG              e.g. v0.1.8 — must match MARKETING_VERSION in project.yml (tag is v-prefixed semver; no -alpha suffix)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SCHEME=MailGent
PROJECT=MailGent.xcodeproj
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"
DERIVED_DATA="${DERIVED_DATA:-.build/DerivedData}"
CONFIG=Release
APP_NAME=MailGent

ASSETS_DIR="$ROOT/Scripts/release/dmg-assets"
BG_PNG="$ASSETS_DIR/background.png"

# Finder window content matches background logical size (552×337; PNG is 2× Retina). Titlebar ≈ 28px.
WIN_W=552
WIN_H=365
ICON_SIZE=64
# Icon centers over empty slots in export.html (2/3 drag + 1/3 Open alias).
ICON_APP_X=114
ICON_APP_Y=102
ICON_APPS_X=258
ICON_APPS_Y=102
ICON_OPEN_X=451
ICON_OPEN_Y=107
OPEN_ALIAS_SRC="$ASSETS_DIR/Open MailGent"
OPEN_ALIAS_NAME="Open MailGent"

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

if [[ ! -f "$BG_PNG" ]]; then
  echo "error: missing ${BG_PNG} (run: swift Scripts/release/dmg-assets/render-background.swift)" >&2
  exit 1
fi

DIST_DIR="$ROOT/dist"
STAGE_DIR="$DIST_DIR/stage"
RW_DMG="$DIST_DIR/${APP_NAME}-${VERSION}-rw.dmg"
DMG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.dmg"

sign_app_bundle() {
  local app_path="$1"
  local identity="$2"
  local framework="$app_path/Contents/Frameworks/MailStore.framework"
  local executable="$app_path/Contents/MacOS/$APP_NAME"
  local entitlements="$ROOT/MailGent/MailGent.entitlements"

  local -a sign_opts=(--force --sign "$identity" --timestamp=none)
  if [[ "$identity" != "-" ]]; then
    sign_opts+=(--options runtime)
  fi

  codesign "${sign_opts[@]}" "$framework/Versions/A/MailStore"
  codesign "${sign_opts[@]}" "$framework"
  if [[ -f "$entitlements" && "$identity" != "-" ]]; then
    codesign "${sign_opts[@]}" --entitlements "$entitlements" "$executable"
    codesign "${sign_opts[@]}" --entitlements "$entitlements" "$app_path"
  else
    codesign "${sign_opts[@]}" "$executable"
    codesign "${sign_opts[@]}" "$app_path"
  fi
  codesign --verify --deep --strict "$app_path"
}

echo "→ MailGent ${VERSION} (${CONFIG}, ${DESTINATION})"

xcodegen generate

# Ad-hoc Release builds cannot load an embedded framework when hardened runtime
# is on — dyld rejects MailStore with "different Team IDs". Developer ID builds
# keep hardened runtime and are re-signed inside-out after xcodebuild.
SIGN_IDENTITY="${MAILGENT_SIGN_IDENTITY:--}"
HARDENED_RUNTIME=NO
if [[ -n "${MAILGENT_SIGN_IDENTITY:-}" ]]; then
  HARDENED_RUNTIME=YES
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES \
  ENABLE_HARDENED_RUNTIME="$HARDENED_RUNTIME" \
  build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIG/${APP_NAME}.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: ${APP_PATH} not found after build" >&2
  exit 1
fi

echo "→ codesign (${SIGN_IDENTITY})"
sign_app_bundle "$APP_PATH" "$SIGN_IDENTITY"

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_PATH" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"
# Finder alias → /Applications/MailGent.app (post-install open shortcut).
# Must preserve FinderInfo (type fapa / creator MACS); plain `cp` drops it and
# double-click opens the bookmark bytes as a text document.
if [[ -f "$OPEN_ALIAS_SRC" ]]; then
  ditto "$OPEN_ALIAS_SRC" "$STAGE_DIR/$OPEN_ALIAS_NAME"
  if command -v SetFile >/dev/null 2>&1; then
    SetFile -t fapa -c MACS "$STAGE_DIR/$OPEN_ALIAS_NAME"
  fi
else
  echo "warning: missing ${OPEN_ALIAS_SRC}; DMG will have no Open MailGent alias" >&2
fi

rm -f "$RW_DMG" "$DMG_PATH"
echo "→ hdiutil create (UDWR staging)"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDRW \
  -fs HFS+ \
  "$RW_DMG"

# Headroom for .background + .DS_Store (srcfolder images are tight).
RW_SIZE_KB="$(hdiutil resize -limits "$RW_DMG" | awk 'END {print int($2)}')"
TARGET_KB=$((RW_SIZE_KB + 20480))
hdiutil resize -size "${TARGET_KB}k" "$RW_DMG"

echo "→ mount + Finder layout"
ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
DEVICE="$(printf '%s\n' "$ATTACH_OUT" | awk 'NR==1 {print $1}')"
VOLUME="$(printf '%s\n' "$ATTACH_OUT" | awk -F'\t' '/\/Volumes\// {print $NF; exit}')"
if [[ -z "$VOLUME" || ! -d "$VOLUME" ]]; then
  echo "error: could not find mounted volume for ${RW_DMG}" >&2
  echo "$ATTACH_OUT" >&2
  hdiutil detach "$DEVICE" -force 2>/dev/null || true
  exit 1
fi
DISK_NAME="$(basename "$VOLUME")"
echo "   mounted at ${VOLUME} (disk \"${DISK_NAME}\")"

# Let Finder register the volume before AppleScript.
sleep 1

mkdir -p "$VOLUME/.background"
cp "$BG_PNG" "$VOLUME/.background/background.png"
rm -rf "$VOLUME/.fseventsd"
mkdir -p "$VOLUME/.fseventsd"
touch "$VOLUME/.fseventsd/no_log"
chflags nohidden "$VOLUME/.background" 2>/dev/null || true

DS_STORE_SRC="$ASSETS_DIR/DS_Store"
LAYOUT_OK=0
# Remake a live Finder alias only when the post-install target exists. On CI
# /Applications/MailGent.app is usually missing — deleting the staged bookmark
# first left step 2 empty (0.15.0). Keep staged unless remake succeeds.
OPEN_ALIAS_TARGET="/Applications/${APP_NAME}.app"
REMAKE_OPEN_ALIAS=0
if [[ -d "$OPEN_ALIAS_TARGET" ]]; then
  REMAKE_OPEN_ALIAS=1
  echo "→ will remake Open alias → ${OPEN_ALIAS_TARGET}"
else
  echo "→ keep staged Open alias (no ${OPEN_ALIAS_TARGET}; typical CI)"
fi

# Prefer live Finder layout; fall back to checked-in DS_Store for headless CI.
# Support folders parked off-canvas for Show Hidden Files (Cmd+Shift+.).
if osascript <<EOF
tell application "Finder"
  tell disk "$DISK_NAME"
    open
    delay 0.8
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    try
      set pathbar visible of container window to false
    end try
    set the bounds of container window to {100, 100, $((100 + WIN_W)), $((100 + WIN_H))}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to $ICON_SIZE
    set background picture of viewOptions to file ".background:background.png"
    set position of item "${APP_NAME}.app" of container window to {$ICON_APP_X, $ICON_APP_Y}
    set position of item "Applications" of container window to {$ICON_APPS_X, $ICON_APPS_Y}
    -- Remake only when target exists. Never delete staged until remake works.
    if $REMAKE_OPEN_ALIAS is 1 then
      try
        make new alias file at container window to (POSIX file "$OPEN_ALIAS_TARGET") with properties {name:"${OPEN_ALIAS_NAME}.new"}
        try
          if exists item "$OPEN_ALIAS_NAME" then
            delete item "$OPEN_ALIAS_NAME"
          end if
        end try
        set name of item "${OPEN_ALIAS_NAME}.new" to "$OPEN_ALIAS_NAME"
      end try
    end if
    try
      set position of item "$OPEN_ALIAS_NAME" of container window to {$ICON_OPEN_X, $ICON_OPEN_Y}
    end try
    try
      set position of item ".background" of container window to {2000, 2000}
    end try
    try
      set position of item ".fseventsd" of container window to {2200, 2000}
    end try
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF
then
  LAYOUT_OK=1
  echo "→ AppleScript Finder layout applied"
  if [[ -f "$VOLUME/.DS_Store" ]]; then
    cp "$VOLUME/.DS_Store" "$DS_STORE_SRC"
    echo "→ saved ${DS_STORE_SRC} for CI / headless builds"
  fi
fi

if [[ "$LAYOUT_OK" -eq 0 ]]; then
  if [[ -f "$DS_STORE_SRC" ]]; then
    echo "→ AppleScript unavailable; applying checked-in .DS_Store"
    cp "$DS_STORE_SRC" "$VOLUME/.DS_Store"
  else
    echo "error: Finder layout failed and no ${DS_STORE_SRC}" >&2
    hdiutil detach "$VOLUME" -force 2>/dev/null || hdiutil detach "$DEVICE" -force 2>/dev/null || true
    exit 1
  fi
fi

if [[ ! -e "$VOLUME/$OPEN_ALIAS_NAME" ]]; then
  echo "error: missing ${OPEN_ALIAS_NAME} on volume after layout (step 2 would be empty)" >&2
  hdiutil detach "$VOLUME" -force 2>/dev/null || hdiutil detach "$DEVICE" -force 2>/dev/null || true
  exit 1
fi
echo "→ Open alias present: ${VOLUME}/${OPEN_ALIAS_NAME}"

chflags hidden "$VOLUME/.background" "$VOLUME/.fseventsd" 2>/dev/null || true

sync
hdiutil detach "$VOLUME" || hdiutil detach "$DEVICE" -force

echo "→ hdiutil convert UDZO → ${DMG_PATH}"
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$RW_DMG"
rm -rf "$STAGE_DIR"

if [[ -n "${MAILGENT_NOTARY_PROFILE:-}" ]]; then
  echo "→ notarize (${MAILGENT_NOTARY_PROFILE})"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$MAILGENT_NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
fi

echo ""
echo "Created: ${DMG_PATH}"
echo "SHA256:  $(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
if [[ -z "${MAILGENT_SIGN_IDENTITY:-}" ]]; then
  echo ""
  echo "Note: ad-hoc build (hardened runtime off). Set MAILGENT_SIGN_IDENTITY + MAILGENT_NOTARY_PROFILE for Gatekeeper-safe distribution."
fi
