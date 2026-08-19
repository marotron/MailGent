# Apple Mail Local-Read First Ship

Label: wayfinder:map

## Destination

Ship MailGent’s first usable product: a lightweight macOS companion that reads Apple Mail’s already-downloaded store, indexes it on-device, and exposes scoped read/search/get to a paired local agent over MCP. Stop when `train/local-read` merges to `main`. OAuth is a later train; local-read stays.

## Notes

- Source: `~/Library/Mail` `.emlx` / `.partial.emlx` only. Surface partial and undownloaded mail; never treat as full. No Envelope Index. No store writes.
- Incremental: FSEvents while running + on-open sweep keyed by path/mtime/inode. No always-on daemon.
- Agent: MailGent is the MCP **server**; first ship is hardened loopback HTTP, one paired `machine-local` agent, account + mailbox allows, read ops only, append-only audit.
- Distribution working assumption: Developer ID + notarization + Full Disk Access (or security-scoped bookmark). MAS sandbox is hostile.
- Reuse ArchMail cores (`EmlxReader`, `MailAccountCatalog`, `MimeMessageParser`, tests/fixtures) into a MailGent `MailStore` target. Do not submodule ArchMail.
- TDD seams (confirmed on ticket 01): MailStore, MailboxIndex, ReadAPI, GrantGate, Pairing, AuditLog.
- One command: `make test` (`xcodegen generate` + `xcodebuild test`).
- Git: long-lived `train/local-read`; topic branches fork from it and PR back. Do not commit live mail, FDA bookmarks, or pairing secrets.
- YAGNI: no OAuth, no helper daemon, no draft ledger, no Mail writes, no Spotlight donation of bodies, no iOS, no built-in assistant.

## Decisions so far

- [Research ArchMail and Apple Mail On-Disk Viability](../mailgent-local-mode/issues/01-research-archmail-ondisk-viability.md) — read path viable; FDA or bookmark; FSEvents + on-open; no Envelope Index; no writes
- [Decide Local-Mode Product Posture](../mailgent-local-mode/issues/02-decide-local-mode-posture.md) — lasting first-ship source; OAuth next train; outbound deferred
- [App Skeleton, FDA Onboarding, Confirm TDD Seams](issues/01-app-skeleton-fda-seams.md) — SwiftUI app + MailStore; FDA fail-closed; six seams confirmed; `make test`
- [MailStore Reader TDD](issues/02-mail-store-reader.md) — fixture `V*` catalog; `.emlx` headers/body; partial + draft `0x10`; attachment metadata + on-demand bytes

## Not yet specified

- Companion read IA among three layouts (ticket 04).
- Copy-paste vs MailGent draft ledger (ticket 06; after read+MCP).
- Menu bar mode: replace `WindowGroup` with `MenuBarExtra` + `Settings` scene so MailGent lives as a status-bar icon with no Dock presence (`LSUIElement = YES` in Info.plist). Companion window opens from the menu bar popover or as a detached panel. Decide at ticket 04 (companion UI) whether the popover is the primary shell or launches a separate window.

## Branches

| Branch | Parent | Issue | Merge target |
| --- | --- | --- | --- |
| `train/local-read` | `research/archmail-ondisk` | — | `main` (ticket 07) |
| `feat/01-app-skeleton` | `train/local-read` | 01 | `train/local-read` |
| `feat/02-mail-store` | `train/local-read` | 02 | `train/local-read` |

## Out of scope

- Gmail/Yahoo OAuth (later `train/oauth`).
- Writing Apple Mail’s store; AppleScript; `mailto:`; MessageUI unless ticket 06 rejects copy-paste.
- Remote agents, mutation approvals, send/trash/delete, smart folders, private scopes, `lan-inference`.
- Mac App Store distribution on this train.
- Submoduling ArchMail.

## Tickets

```mermaid
flowchart TD
  chart["Chart map + seven stage tickets"]
  skeleton["01 · App skeleton, FDA, confirm seams"]
  store["02 · MailStore reader TDD"]
  index["03 · MailboxIndex + ReadAPI TDD"]
  ui["04 · Companion read UI prototype then shell"]
  mcp["05 · MCP read, pairing, grants, audit"]
  drafts["06 · Draft outbound prototype"]
  merge["07 · Merge train, leave OAuth later"]
  chart --> skeleton
  skeleton --> store
  store --> index
  index --> ui
  ui --> mcp
  mcp --> drafts
  mcp --> merge
```

| # | Title | Type | Status |
|---|-------|------|--------|
| 01 | [App Skeleton, FDA Onboarding, Confirm TDD Seams](issues/01-app-skeleton-fda-seams.md) | task | resolved |
| 02 | [MailStore Reader TDD](issues/02-mail-store-reader.md) | task | resolved |
| 03 | [MailboxIndex and ReadAPI TDD](issues/03-mailbox-index-read-api.md) | task | open |
| 04 | [Companion Read UI Prototype Then Shell](issues/04-companion-read-ui.md) | prototype | open |
| 05 | [MCP Read, Pairing, Grants, Audit](issues/05-mcp-pairing-grants-audit.md) | task | open |
| 06 | [Draft Outbound Prototype](issues/06-draft-outbound.md) | prototype | open |
| 07 | [Merge Local-Read Train](issues/07-merge-train.md) | task | open |
