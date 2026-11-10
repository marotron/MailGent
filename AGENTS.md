## Agent skills

### Issue tracker

**Future features / fog / deferred work → GitHub Issues** on `marotron/MailGent` (labels `roadmap`, `fog`, `next-version` — same pattern as QuotAI). Active wayfinder maps/specs/prototypes may still live under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.

### UI element inventory

Reusable control types, icons, and placement rules: `docs/ui-inventory.md`.

**Visual features:** follow the standing process in global `swift-implementation-plans.mdc` (Visual features) and `.cursor/rules/ui-inventory.mdc`. MailGent paths: HTML proto under `.scratch/<feature>/` → approved proto is source of truth → reuse inventory by **job** → compose locally for gaps → **ask** before adding inventory types after dogfood. Do not add inventory rows mid-feature; approved proto wins over inventory convenience.

### App icon / logo

Candidate-first. Sketch in `.scratch/app-icon/candidates/`; do not write `AppIcon` until the user ships a named candidate. See `docs/agents/app-icon.md`.

### License / liability / Homebrew

Apache-2.0 + `NOTICE`; name and icon stay ours. Homebrew cask is **future** (after a notarized GitHub Release). Sign only with the **personal** Apple ID — never an employer/company team. See `docs/agents/licensing.md`.

### Versioning

Open the next version as a **candidate** when user-facing work starts: `X.Y.Z-rc.1` → `rc.2` → ship `X.Y.Z` (Apple `MARKETING_VERSION` stays plain `X.Y.Z`; `-rc.N` is display/MCP only). While candidate, keep notes under `## [Unreleased]`; promote CHANGELOG + full README + PRIVACY only on ship. See `.cursor/rules/versioning.mdc` (MailGent dogfood — not global yet).

Ship tags must be **signed** and only when `releaseCandidate == 0`: `git tag -s vX.Y.Z -m "…"`, then `git verify-tag` before push. Never lightweight or unsigned annotated ship tags.

After bumping version, run `python3 ../scripts/update-dev-index.py` (from repo root: `python3 ~/dev/scripts/update-dev-index.py`) to refresh `~/dev/INDEX.md`.

### MCP dogfood

When changing MCP tools / propose-await behaviour: update `Scripts/mcp-tester/` and matching `Scripts/tests/*` harnesses (`--self-check`). See `.cursor/rules/mcp-dogfood.mdc`.

### CI/CD

PR and `main` run `make test`; tag `v*` strips screenshot helpers, then test → DMG → GitHub pre-release. See `docs/agents/ci-cd.md`.

### Screenshots

Local fixture capture; Release CI strips helpers before DMG. See `docs/agents/screenshots.md`.

