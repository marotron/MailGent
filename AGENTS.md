## Agent skills

### Issue tracker

Issues live as markdown under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Domain docs

Single-context: `CONTEXT.md` + `docs/adr/` at repo root. See `docs/agents/domain.md`.

### App icon / logo

Candidate-first. Sketch in `.scratch/app-icon/candidates/`; do not write `AppIcon` until the user ships a named candidate. See `docs/agents/app-icon.md`.

### License / liability / Homebrew

Apache-2.0 + `NOTICE`; name and icon stay ours. Homebrew cask is **future** (after a notarized GitHub Release). Sign only with the **personal** Apple ID — never company / `employer@example.com`. See `docs/agents/licensing.md`.

### Versioning

Bump `MARKETING_VERSION` only when a user-facing change is ready to land. **Always update root `CHANGELOG.md` in the same commit** — see `.cursor/rules/versioning.mdc`.
