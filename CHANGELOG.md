# Changelog

All notable changes to MailGent are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/). **Every version bump must add a new `## [X.Y.Z]` section here** (same commit as `project.yml` / README / MCP version). See `.cursor/rules/versioning.mdc`.

Release sections use semver only (`## [0.4.0]`). The **alpha** stage is called out in README, About, and GitHub Release titles — not in `MARKETING_VERSION` or git tags.

## [0.8.2] - 2026-10-04

### Changed

- Pass Desk rule tags: tighter vertical alignment for the mode chip and value, slightly roomier corner radius on each rule row.

## [0.8.1] - 2026-10-04

### Fixed

- Release builds no longer plant or default to fixture mail — live Mail only. Fixture source remains available in Debug builds for local development.

## [0.8.0] - 2026-10-04

### Added

- Access Log Formatted Response preview — `get` shows a flat `MessageAccessCard` with Preview + Open in Apple Mail; `search` / `list` / `listNew` use `SearchResultCard` hits; `get_attachment` uses an attach-for row + `FileCard` with fail-closed Preview for denied / missing / too-large.
- Access Log Request/Response mode chrome: Formatted (default) plus JSON Pretty / Raw (picking Pretty or Raw selects JSON).

### Changed

- Access Log Formatted Response stays truth-first (only fields/bytes the agent received); Preview and Open in Apple Mail are Access Log affordances on top. Companion Read MIME Pretty/Raw and attachment rows are unchanged.
- Access Log message/search cards no longer open Companion Read on body tap — only the Preview button does (`get` / search / list open Companion Read; `get_attachment` Preview re-exports the file).
- Access Log secondary actions (Preview, Open in Apple Mail) are icon-only and expand to icon + label on hover.
- Access Log Request/Response mode chrome only raises the active choice (Formatted, or JSON Pretty/Raw).
- Open in Apple Mail uses the SF Symbol `arrow.up.right.square` (hierarchical), matching Preview’s `eye`.

## [0.7.0] - 2026-10-03

### Added

- Open in Apple Mail — Companion Read and Access Log message preview open the selected message via `message://` using its RFC Message-ID (fail closed when the header is missing).
- Shared secondary-action chrome (icon + label) for handoffs; Access Log `attach` rows label the handoff **Open message in Apple Mail** so it is clear the parent email opens, not the file.

## [0.6.0] - 2026-10-03

### Added

- MCP `get_attachment` — when Scope allows the message and grant fields include Attachment Content, writes attachment bytes to a unique local temp file and returns its `path` (25 MiB hard cap; partial/undownloaded → `not_available`). Access Log shows an `attach` row with metadata only (no file bytes).

### Fixed

- Access Log `attach` rows show `attachmentContentAccess` in the list and the delivered filename (or not granted / not available / too large) in Attachment Content, instead of always “none in this response”. Locked legend only appears when a field is actually locked.

## [0.5.1] - 2026-09-30

### Added

- Access Log list chips for effectful Pass/Block applications (green ✓ / red ✗; count only when that polarity hit more than once).
- Access Log message preview tints field chips green/red for Pass-revealed / Block-withheld fields, and marks those sections with the Grant Desk–style rule nick (✓/✗ + letter).
- Grant Desk Access asset list uses compact Pass/Block count badges (circular ✓/✗ + number) and a wider left pane.

### Fixed

- From rule matchers (`ENDS` / `EXACT` / …) now compare against the mailbox address inside `Name <addr@host>`, so domain Passes like `ENDS @ovoenergy.com` fire on real Apple Mail From lines.
- Detached windows no longer flash-close when opened from the menu bar (MenuBarExtra teardown was treated as a traffic-light close while the open click was still the current event).

### Changed

- Rule field application is explicitly a Pass/Block overwrite on the Scope base (`applyOverlays`); UI copy clarifies mailbox allow vs field grant.

## [0.5.0] - 2026-09-30

### Added

- **Rules** — Pass and Block polarity with optional When date windows on already-allowed messages (From/Subject match, AND/OR join, per-agent enablement on Scope placements). Persisted in `rules.json`; Grant Desk Rules tab + Access preview shows via-rule field changes.

### Changed

- Replaces Passes (`passes.json` / Pass types) with Rules (`rules.json` / `GrantRule`). No in-app migration from `passes.json`.


## [0.4.0] - 2026-09-29

### Added

- **Passes** — conditional field green lights on already-allowed messages (From/Subject match rules, AND/OR join, per-agent enablement on Scope placements). Persisted in `passes.json`; Grant Desk Passes tab + Access preview shows via-pass reveals.

## [0.3.1] - 2026-09-28

### Fixed

- Grant saves no longer replace a non-empty `grants.json` with an empty list when pairing an agent or saving an incidental edit. Explicit Clear and agent revoke still remove grants. Rows for an agent id that is not currently paired stay on disk.
- Before a save that shrinks the grant file, the previous file is copied to `grants.json.bak`.

### Added

- Grant load and save logging (`[MailGent][grants]`) with file size, decode errors, per-agent counts, placement keys, and the reason for each write. No message bodies or pairing credentials.

## [0.3.0] - 2026-09-04

### Added

- **Multi-agent pairing** — Pair Cursor and Pair Grok Bot as independent machine-local agents on the same loopback MCP URL (distinct Bearers).
- Companion **half-width agent cards** (2-column grid) with per-agent snippet, revoke, grant count, and selection for Grant Desk.
- Grant Desk **agent picker**; allows/denies stay per `agentID`. Leak guard policy remains global.
- `GrokMark` asset + `AgentGlyph` support for Grok Bot; Cursor keeps auto-sync into `~/.cursor/mcp.json` (Grok Bot is copyable snippet only).
- `pairing.json` **v2** (agents array + selectedAgentID) with automatic v1→v2 migration; `grants.json` persists the union of all agents’ grants.

### Changed

- Startup restores all persisted agents; auto-pairs **Cursor only** when none exist. Revoke no longer re-pairs another agent.
- Menu bar / status shows selected name, or `N agents` when more than one is paired.
- Grok pairing label is **Grok Bot** (existing `Grok` entries migrate on restore). `GrokMark` uses macOS-style rounded corners.
- Access log success icon for a zero-result search, list, new, or placements call is secondary grey; hits with results stay green.

## [0.2.0] - 2026-08-31

### Added

- **Outbound leak guard** — on-device scan of subject and body before paired agents receive mail; opt in per placement in Grant Desk → Scope.
- Grant Desk **Privacy** tab: built-in detectors (API keys, JWT, password patterns, and more), custom literal/wildcard/regex filters, subject/body hit modes (redact spans or block whole field), with expandable info panels matching Scope/Access.
- MCP `get` and list/search summaries expose `subjectAccess` / `bodyAccess` (`granted`, `not_granted`, `sanitized`, `withheld_confidential`), `subjectAccessReason` / `bodyAccessReason` (`grant`, `leak_guard`), and `sanitizedRules` when disclosed.
- Access log shows sanitized spans and withheld fields; hover reveals originals; audit refs record per-hit leak detections for badges and detail.
- Leak guard policy persisted in `~/Library/Application Support/MailGent/sensitive-filter.json`.

### Changed

- Access log leak-guard chrome uses purple (not warning orange); sanitized fields use a purple tint instead of a dashed underline.
- Access log leak-hit badges and detection rows show original → replacement; stealth audits keep human-visible sanitized markers.

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
