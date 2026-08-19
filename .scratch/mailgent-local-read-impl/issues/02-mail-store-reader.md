# MailStore Reader TDD

Type: task
Status: resolved
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

## Answer

**Yes.** `feat/02-mail-store` (parent `train/local-read`, after fast-forwarding ticket 01) exposes a public `MailStore` seam over fixture `V*` trees. `make test`: 6 MailStore tests + 3 access tests. CI never opens live `~/Library/Mail`.

Public API:

- `accounts()` — UUID folders under newest `V*`; empty UUID dirs skipped
- `mailboxes(in:)` / `messageIDs(in:mailbox:)` — `.mbox` stems; one id per `.emlx` / `.partial.emlx` pair
- `message(accountID:mailbox:id:)` — From/To/Subject + plain body; `isPartial` from filename; `isDraft` from plist `flags` bit `0x10`
- `attachmentData(...)` — bytes only when asked; `MailMessage.attachments` is filename + `byteCount` from the filesystem

Partial wins when both `7.emlx` and `7.partial.emlx` exist. Read/flagged bits are **not** named: only draft `0x10` is fixture-proven (ArchMail). Accounts4.sqlite display names and full MIME multipart/RFC2047 walk are YAGNI until index/UI need them.

## Comments

- 2026-08-19 — TDD six vertical slices on the MailStore seam. Internals (`parseEmlx`, catalog walk) are not tested directly.
