#!/usr/bin/env bash
# GitHub release notes: CHANGELOG section(s) since the previous tag through this
# version, then install / Gatekeeper body.
#
# When a semver is skipped (e.g. 0.8.2 → 0.10.0), every CHANGELOG section after
# the previous tag and up to this version is included.
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

# Previous released tag (semver only), if any — used to gather skipped-version sections.
PREV_VERSION=""
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
  PREV_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' "v${VERSION}^" 2>/dev/null || true)"
else
  PREV_TAG="$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || true)"
fi
if [[ -n "${PREV_TAG}" ]]; then
  PREV_VERSION="${PREV_TAG#v}"
  PREV_VERSION="${PREV_VERSION%%-*}"
fi

ver_key() {
  # Portable X.Y.Z → zero-padded comparable string.
  local v="$1"
  local major minor patch
  IFS=. read -r major minor patch _ <<<"${v}."
  printf '%05d%05d%05d' "${major:-0}" "${minor:-0}" "${patch:-0}"
}

CUR_KEY="$(ver_key "$VERSION")"
PREV_KEY=""
if [[ -n "$PREV_VERSION" ]]; then
  PREV_KEY="$(ver_key "$PREV_VERSION")"
fi

CHANGES="$(
  CUR_KEY="$CUR_KEY" PREV_KEY="$PREV_KEY" awk '
    BEGIN {
      cur_key = ENVIRON["CUR_KEY"]
      prev_key = ENVIRON["PREV_KEY"]
    }
    /^## \[/ {
      if (printing) exit
      section = $0
      sub(/^## \[/, "", section)
      sub(/\].*$/, "", section)
      # Keep only leading X.Y.Z (drop dates / suffixes).
      split(section, parts, /[^0-9.]/)
      section = parts[1]
      n = split(section, a, ".")
      section_key = sprintf("%05d%05d%05d", a[1]+0, (n>=2?a[2]+0:0), (n>=3?a[3]+0:0))
      if (section_key <= cur_key && (prev_key == "" || section_key > prev_key)) {
        printing = 1
        print
        next
      }
      next
    }
    printing { print }
  ' CHANGELOG.md
)"

if [[ -z "$CHANGES" ]]; then
  CHANGES="$(
    awk -v ver="$VERSION" '
      $0 ~ "^## \\[" ver "\\]" { found = 1; print; next }
      found && $0 ~ "^## \\[" { exit }
      found { print }
    ' CHANGELOG.md
  )"
fi
if [[ -z "$CHANGES" ]]; then
  echo "error: CHANGELOG.md has no section ## [${VERSION}] (or range since ${PREV_VERSION:-none})" >&2
  exit 1
fi

mkdir -p dist
{
  if [[ -n "${PREV_VERSION}" && "${PREV_VERSION}" != "${VERSION}" ]]; then
    printf 'Changes since **%s**\n\n' "${PREV_VERSION}"
  fi
  printf '%s\n' "$CHANGES"
  echo
  sed "s/@VERSION@/${VERSION}/g" .github/RELEASE_BODY.md
} > dist/RELEASE_NOTES.md

echo "Wrote dist/RELEASE_NOTES.md for ${VERSION} (since ${PREV_VERSION:-beginning})"
