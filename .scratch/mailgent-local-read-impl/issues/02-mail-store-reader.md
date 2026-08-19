# MailStore Reader TDD

Type: task
Status: open
Blocked by: 01

## Question

Does `MailStore`, given a fixture `V*` Mail tree, list accounts, mailboxes, and messages, parse `.emlx` to headers + body + flags, prefer `.partial.emlx` with `isPartial`, and expose attachment metadata without reading Apple Mail’s live store in CI?

## Context

**Branch:** `feat/02-mail-store` off `train/local-read`.

TDD at the **MailStore** seam only. Adapt ArchMail cores (`MailAccountCatalog`, `EmlxReader`, `MimeMessageParser`) and their fixtures; do not submodule ArchMail. Loop: one failing test → minimal code → next test. Expected values are literals from fixtures, not recomputed the way the parser does.

Vertical slices:

1. List account folders under a fixture `V*` tree.
2. List mailboxes + message ids.
3. Parse one full `.emlx` to headers + body.
4. Prefer `.partial.emlx` when both exist; expose `isPartial`.
5. Flags that matter for read (read/unread, flagged, draft) — only what fixtures prove.
6. External attachments by metadata; body fetch of attachment bytes only when asked.

Context7: Foundation file APIs / Swift Testing as needed.

## Verify

ArchMail-equivalent fixture tests pass in MailGent; no live `~/Library/Mail` in CI.

YAGNI: no index, no MCP, no UI beyond what ticket 01 already launched.

## Inputs

- [01 · App Skeleton, FDA Onboarding, Confirm TDD Seams](01-app-skeleton-fda-seams.md) — seams must be confirmed first.
- ArchMail: `EmlxReader.swift`, `MailAccountCatalog.swift`, `MimeMessageParser.swift` and tests/fixtures.
