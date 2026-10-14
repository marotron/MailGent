#!/usr/bin/env bash
# SCREENSHOT_DEMO_POLICY — run on the Release CI checkout before `make dmg`.
# Workflow: docs/agents/screenshots.md
#
# Local screenshots keep CompanionDemoPolicy / fixture helpers in the repo.
# Tag builds strip that scaffolding from the runner workspace so the Release
# binary is built without screenshot-only facilitation code.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MARKER=SCREENSHOT_DEMO_POLICY

echo "→ Stripping ${MARKER} scaffolding from release checkout"

python3 - <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(".").resolve()
MARKER = "SCREENSHOT_DEMO_POLICY"

DELETE_PATHS = [
    "MailGent/CompanionDemoPolicy.swift",
    "MailGent/CompanionScreenshotDemo.swift",
    "MailGentTests/CompanionDemoPolicyTests.swift",
    "Scripts/release/capture-named-window.swift",
    ".github/workflows/screenshots.yml",
]

# #if DEBUG … #endif blocks that mention any of these are screenshot-only.
BLOCK_HINTS = (
    MARKER,
    "CompanionDemoPolicy",
    "CompanionScreenshotDemo",
    "applyScreenshotDemoPolicy",
    "restoreScreenshotDemoPolicy",
    "finishScreenshotDemoPolicyIfPending",
    "hasScreenshotDemoPolicyBackup",
    "pendingScreenshotDemoPolicy",
    "screenshotDemoScene",
    "applyScreenshotDemoSceneIfNeeded",
    "case screenshotDemo",
    "MAILGENT_SCREENSHOT_POLICY",
    "MAILGENT_SCREENSHOT_SCENE",
)

SWIFT_TARGETS = [
    "MailGent/AgentBridge.swift",
    "MailGent/CompanionSession.swift",
    "MailGent/CompanionWindow.swift",
    "MailGent/GrantDeskView.swift",
]


def strip_debug_blocks(text: str) -> str:
    """Remove #if DEBUG … #endif regions whose body matches screenshot hints."""
    lines = text.splitlines(keepends=True)
    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r"^[ \t]*#if DEBUG\b", line):
            start = i
            depth = 1
            i += 1
            while i < len(lines) and depth > 0:
                if re.match(r"^[ \t]*#if\b", lines[i]):
                    depth += 1
                elif re.match(r"^[ \t]*#endif\b", lines[i]):
                    depth -= 1
                i += 1
            block = "".join(lines[start:i])
            if any(hint in block for hint in BLOCK_HINTS):
                # Drop trailing blank line left by the removed block.
                if out and out[-1].strip() == "" and (i >= len(lines) or lines[i].strip() == ""):
                    out.pop()
                continue
            out.extend(lines[start:i])
            continue
        out.append(line)
        i += 1
    return "".join(out)


def scrub_marker_comments(text: str) -> str:
    """Remove leftover single-line comments that only name the marker."""
    cleaned: list[str] = []
    for line in text.splitlines(keepends=True):
        if MARKER in line and re.match(r"^[ \t]*//", line):
            continue
        cleaned.append(line)
    return "".join(cleaned)


removed_files = 0
for rel in DELETE_PATHS:
    path = ROOT / rel
    if path.exists():
        path.unlink()
        removed_files += 1
        print(f"  deleted {rel}")

edited = 0
for rel in SWIFT_TARGETS:
    path = ROOT / rel
    if not path.exists():
        print(f"  skip missing {rel}", file=sys.stderr)
        continue
    original = path.read_text(encoding="utf-8")
    updated = scrub_marker_comments(strip_debug_blocks(original))
    # Collapse runs of 3+ blank lines left by removals.
    updated = re.sub(r"\n{3,}", "\n\n", updated)
    if updated != original:
        path.write_text(updated, encoding="utf-8")
        edited += 1
        print(f"  scrubbed {rel}")

print(f"→ Removed {removed_files} file(s), scrubbed {edited} Swift file(s)")
PY

# Drop local-only screenshot Make targets from this checkout (not shipped; hygiene).
if [[ -f Makefile ]]; then
  python3 - <<'PY'
from pathlib import Path
import re
text = Path("Makefile").read_text(encoding="utf-8")
text2 = re.sub(
    r"\n# SCREENSHOT_DEMO_POLICY[^\n]*\nscreenshots:\n(?:\t[^\n]*\n)*\nscreenshots-ci:\n(?:\t[^\n]*\n)*",
    "\n",
    text,
)
text2 = text2.replace(" screenshots screenshots-ci", "")
text2 = re.sub(
    r'\n\t@echo "→ DMG ready\. Optional docs pass: make screenshots / make screenshots-ci"\n'
    r'\t@echo "  GitHub: Screenshots workflow on tag push \(artifacts \+ release attach\)"\n'
    r'\t@echo ""\n',
    '\n\t@echo ""\n\t@echo "→ DMG ready."\n\t@echo ""\n',
    text2,
)
if text2 != text:
    Path("Makefile").write_text(text2, encoding="utf-8")
    print("  scrubbed Makefile")
PY
fi

# Local screenshots.sh is not compiled into the app; drop it on the release runner.
if [[ -f Scripts/release/screenshots.sh ]]; then
  rm -f Scripts/release/screenshots.sh
  echo "  deleted Scripts/release/screenshots.sh"
fi

# Compile tree only — docs / release.yml may still name the helper.
if grep -RIn --include='*.swift' \
    -e "$MARKER" -e 'CompanionDemoPolicy' -e 'CompanionScreenshotDemo' \
    MailGent MailGentTests 2>/dev/null; then
  echo "error: screenshot demo policy references remain in Swift sources" >&2
  exit 1
fi

echo "→ Strip ok (Swift sources clear of ${MARKER} / CompanionDemoPolicy / CompanionScreenshotDemo)"
