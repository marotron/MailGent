#!/usr/bin/env bash
# GitHub release notes: this version's CHANGELOG section, then install / Gatekeeper body.
#
# Version comes from $1, RELEASE_TAG (vX.Y.Z), or MARKETING_VERSION in project.yml.
# Writes dist/RELEASE_NOTES.md (dist/ is gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

VERSION="${1:-${RELEASE_TAG:-}}"
VERSION="${VERSION#v}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(
    sed -n 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"\([^"]*\)".*/\1/p' project.yml | head -1
  )"
fi
if [[ -z "$VERSION" ]]; then
  echo "error: could not determine version" >&2
  exit 1
fi

CHANGES="$(
  awk -v ver="$VERSION" '
    $0 ~ "^## \\[" ver "\\]" { found = 1; print; next }
    found && $0 ~ "^## \\[" { exit }
    found { print }
  ' CHANGELOG.md
)"
if [[ -z "$CHANGES" ]]; then
  echo "error: CHANGELOG.md has no section ## [${VERSION}]" >&2
  exit 1
fi

mkdir -p dist
{
  printf '%s\n' "$CHANGES"
  echo
  sed "s/@VERSION@/${VERSION}/g" .github/RELEASE_BODY.md
} > dist/RELEASE_NOTES.md

echo "Wrote dist/RELEASE_NOTES.md for ${VERSION}"
