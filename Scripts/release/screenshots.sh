#!/usr/bin/env bash
# SCREENSHOT_DEMO_POLICY — local DEBUG helper for docs screenshots (fixture fake data).
# Release CI strips this scaffolding via strip-screenshot-demo-policy.sh before DMG.
#
# Interactive:
#   make screenshots
#   ./Scripts/release/screenshots.sh
#
# Auto-capture (still local — not a GitHub job):
#   ./Scripts/release/screenshots.sh --ci
#   Writes PNGs under dist/screenshots/ and exits non-zero if any scene fails.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

CI_MODE=0
if [[ "${1:-}" == "--ci" ]]; then
  CI_MODE=1
fi

POLICY_SWIFT="$ROOT/MailGent/CompanionDemoPolicy.swift"
if [[ ! -f "$POLICY_SWIFT" ]]; then
  echo "error: CompanionDemoPolicy.swift missing — screenshot demo policy was removed" >&2
  exit 1
fi

VERSION="$(
  sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)".*/\1/p' project.yml | head -1
)"
if [[ -z "$VERSION" ]]; then
  echo "error: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

SCHEME=MailGent
PROJECT=MailGent.xcodeproj
DESTINATION="${DESTINATION:-platform=macOS,arch=arm64}"
DERIVED_DATA="${DERIVED_DATA:-.build/DerivedData}"
APP="$DERIVED_DATA/Build/Products/Debug/MailGent.app"
REFS_DIR="$ROOT/docs/agents/assets/refs/${VERSION}"
SHOTS_DIR="$ROOT/docs/screenshots"
OUT_DIR="$ROOT/dist/screenshots"
READY_MARKER="${HOME}/Library/Application Support/MailGent/mailgent-screenshot-ready"
CAPTURE_SWIFT="$ROOT/Scripts/release/capture-named-window.swift"

SCENES=(
  "control-center|MailGent"
  "grant-desk-scope|Grant desk"
  "grant-desk-access|Grant desk"
  "grant-desk-rules|Grant desk"
  "grant-desk-privacy|Grant desk"
)

echo "→ MailGent ${VERSION} screenshot pass (DEBUG + screenshot demo policy${CI_MODE:+, CI})"
echo

xcodegen generate
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -configuration Debug \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES \
  build

killall -9 MailGent >/dev/null 2>&1 || true
sleep 0.3

mkdir -p "$REFS_DIR" "$SHOTS_DIR"

if [[ "$CI_MODE" -eq 0 ]]; then
  echo "→ Launching Debug app with MAILGENT_SCREENSHOT_POLICY=1"
  echo "   Fixture index → plant 2-account grants + Shared rules A–D → open Companion + Grant Desk"
  MAILGENT_SCREENSHOT_POLICY=1 MAILGENT_VERBOSE=1 open "$APP"

  cat <<EOF

────────────────────────────────────────────────────────
Screenshot checklist (version ${VERSION})
────────────────────────────────────────────────────────
Policy is live. Capture (⇧⌘5 → Window) into:

  docs/screenshots/control-center.png      Companion home
  docs/screenshots/grant-desk-scope.png    Grant Desk · Cursor · Scope
  docs/screenshots/grant-desk-access.png   Grant Desk · Cursor · Access  (expect 2 assets)
  docs/screenshots/grant-desk-rules.png    Grant Desk · Shared · Rules   (Used on 2 placements)
  docs/screenshots/grant-desk-privacy.png  Grant Desk · Shared · Privacy
  docs/screenshots/access-log.png          Access Log (optional this pass)

Or auto-capture locally:
  ./Scripts/release/screenshots.sh --ci

Also drop HQ refs here (optional):
  ${REFS_DIR}/

When finished:
  Companion → Last ingest → Restore real policy

Remove this pipeline before production:
  grep -n SCREENSHOT_DEMO_POLICY -r MailGent Scripts Makefile .github
────────────────────────────────────────────────────────
EOF
  exit 0
fi

# ── CI mode ──────────────────────────────────────────────────────────────────
mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR"/*.png

warm_screencapture() {
  # macOS 15 may show a one-time private-window-picker consent; warm it up.
  screencapture -x /tmp/mailgent-screenshot-warm.png || true
  sleep 2
  osascript -e 'tell application "System Events" to tell (first process whose name contains "UserNotificationCenter") to click button "Allow" of window 1' 2>/dev/null || true
  sleep 1
  rm -f /tmp/mailgent-screenshot-warm.png
}

wait_for_ready() {
  local scene="$1"
  local deadline=$((SECONDS + 180))
  rm -f "$READY_MARKER"
  while (( SECONDS < deadline )); do
    if [[ -f "$READY_MARKER" ]]; then
      local body
      body="$(tr -d '\n' <"$READY_MARKER" || true)"
      if [[ "$body" == "$scene" || -n "$body" ]]; then
        sleep 0.4
        return 0
      fi
    fi
    sleep 0.5
  done
  echo "error: timed out waiting for ready marker (scene=$scene)" >&2
  return 1
}

capture_scene() {
  local scene="$1"
  local title="$2"
  local out="$OUT_DIR/${scene}.png"

  echo "→ Scene ${scene} (window ~ \"${title}\")"
  killall -9 MailGent >/dev/null 2>&1 || true
  sleep 0.4
  rm -f "$READY_MARKER"

  MAILGENT_SCREENSHOT_POLICY=1 \
    MAILGENT_SCREENSHOT_SCENE="$scene" \
    MAILGENT_VERBOSE=1 \
    open "$APP"

  wait_for_ready "$scene"
  sleep 0.6
  swift "$CAPTURE_SWIFT" "$title" "$out"
  killall -9 MailGent >/dev/null 2>&1 || true
  sleep 0.3

  if [[ ! -s "$out" ]]; then
    echo "error: empty capture $out" >&2
    return 1
  fi
  echo "   wrote $out ($(wc -c <"$out" | tr -d ' ') bytes)"
}

warm_screencapture

FAILED=0
for entry in "${SCENES[@]}"; do
  scene="${entry%%|*}"
  title="${entry##*|}"
  if ! capture_scene "$scene" "$title"; then
    FAILED=1
  fi
done

echo
echo "→ CI screenshots in $OUT_DIR"
ls -la "$OUT_DIR" || true

if [[ "$FAILED" -ne 0 ]]; then
  echo "error: one or more screenshot scenes failed" >&2
  exit 1
fi
