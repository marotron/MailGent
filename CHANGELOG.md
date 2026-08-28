# Changelog

All notable changes to MailGent are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/). **Every version bump must add a new `## [X.Y.Z]` section here** (same commit as `project.yml` / README / MCP version). See `.cursor/rules/versioning.mdc`.

Release sections use semver only (`## [0.1.9]`). The **alpha** stage is called out in README, About, and GitHub Release titles — not in `MARKETING_VERSION` or git tags.

## [0.1.9] - 2026-08-28

### Fixed

- Mail timestamps display in local time consistently (access log message cards, Companion Read, status JSON).
- Release DMG launches on install — ad-hoc builds re-sign MailStore and disable hardened runtime so dyld no longer aborts at startup.

## [0.1.8] - 2026-08-28

### Added

- About MailGent window (app menu and menu item between Settings and Quit) with bundled changelog viewer; menu-bar version label opens the changelog directly.

### Fixed

- Settings loopback MCP port field no longer inserts thousands separators (e.g. 8788).
- Changelog viewer renders version sections and bullet lists instead of a single collapsed paragraph.

## [0.1.7] - 2026-08-28

### Added

- `make dmg` / `make release` build `dist/MailGent-<version>.dmg` for GitHub Releases.
- Release workflow on `v*` tags attaches the DMG; release notes warn about Gatekeeper when unsigned.

## [0.1.6] - 2026-08-28

### Added

- Loopback MCP binds on launch; during full reindex, data tools return HTTP 503 with indexing progress (`state`, `indexedSoFar`, `totalHint`, `currentTask`). `status` stays reachable for polling.

## [0.1.5] - 2026-08-28

### Added

- Settings → General → **Loopback MCP port** (default 8788); listener rebinds and Cursor `mcp.json` URL updates when changed.

## [0.1.4] - 2026-08-28

### Fixed

- MCP `get` returns plain text for HTML-only messages (tags stripped) when no plain part exists.
- Default loopback MCP port moved from 8787 to 8788 to avoid clashing with Cursor OAuth callbacks.

### Changed

- MCP tool descriptions clarify that `search`, `list`, and `list_new` return headers only; use `get` to read body.

## [0.1.3] - 2026-08-28

### Changed

- Menu **Changes** chip shows the ingest window as a start–end range with compact duration (e.g. `12:15–12:31 (16m)`).

## [0.1.2] - 2026-08-28

### Changed

- Menu status times use clock + elapsed chips; dates from yesterday or earlier show the calendar date instead of looking like today.

## [0.1.1] - 2026-08-28

### Fixed

- Incremental ingest reports arrivals vs removals (`+44 −2277 → −2233`); Trash/Junk copies are no longer counted as new mail.

### Added

- MCP `list_new` tool — list messages from the last ingest pass only (same header shape as `list` / `search`).

### Changed

- README and PRIVACY describe Mail access as readable `~/Library/Mail` (Full Disk Access or chosen folder), not FDA-only wording.

## [0.1.0] - 2026-08-24

First tagged alpha (`v0.1.0-alpha.1`).

### Added

- Apple Mail `.emlx` local-read from `~/Library/Mail` with on-device SQLite FTS.
- Loopback MCP on `127.0.0.1:8787` for one paired `machine-local` agent.
- Grant desk: account/mailbox scope, From/To/date filters, deny carve-outs, field caps (Cc, body, attachments).
- Append-only access log with grant-aware detail and exact MCP JSON captured per call.
- In-memory MailGent-owned draft ledger (not written into Mail.app).
- MCP tools: `search`, `list`, `list_placements`, `get`, `status`, `update`, `create_draft`, `update_draft`, `set_source`.
- `bodyAccess` on `get` when the grant denies body.
- Inline MIME attachment metadata on `get`.
- Apache-2.0 license, NOTICE, and honest README/PRIVACY for the alpha slice.
