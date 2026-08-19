# MailboxIndex and ReadAPI TDD

Type: task
Status: resolved
Blocked by: 02

## Question

Does a second ingest of a fixture tree report only the planted new `.emlx` as new, and do `search` / `get` / cursor pagination return known fixture literals with account + placement visible and partial messages marked?

## Context

**Branch:** `feat/03-mailbox-index` off `train/local-read`.

TDD at **MailboxIndex** + **ReadAPI** (no grants yet — index is a human/local cache).

- First ingest builds an on-disk SQLite FTS index of granted-later fields: account, mailbox/placement, from/to, date, subject, body.
- Second ingest with one new `.emlx` reports that id as new; unchanged files are not re-parsed if mtime/inode identity matches. Default while running: FSEvents + on-open sweep; **no always-on daemon**.
- `search` / `get` / cursor pagination; unified listing still shows account + placement.
- Stale/incomplete: partial messages searchable but marked; missing body is `not_available` to later agent callers.

If “what’s new” is hard to reason about on paper, a tiny `/prototype` **logic** CLI in `MailStore/Prototype/` (one command, in-memory, print full state after each ingest). Capture the verdict on this issue; keep the prototype off `main`.

## Verify

Fixture ingest → search hits match known literals; incremental second pass only emits the planted new message.

YAGNI: no GrantGate, no MCP, no daemon.

## Inputs

- [02 · MailStore Reader TDD](02-mail-store-reader.md)
- Canonical mailbox model: `.scratch/mailgent-product-definition/issues/05-define-canonical-mailbox-model.md`
- Cadence: [ArchMail on-disk viability](../../mailgent-local-mode/research/archmail-ondisk-viability.md)

## Answer

**Yes.** `feat/03-mailbox-index` adds `MailboxIndex` (SQLite FTS5 cache) and `ReadAPI` (paged list/search/get/listPlacements) over fixture `V*` trees. `make test`: 16 MailStore-module tests + 3 access tests. No live `~/Library/Mail`. No prototype CLI — identity skip (path/inode/mtime/size via `lstat`) was clear on paper.

**MailboxIndex**

- `ingest()` walks `MailStore`, upserts account + placement + from/to/date/subject/body + `isPartial`
- Second ingest of an unchanged tree returns `new: []`; a planted `.emlx` is the only new ref
- Same id with changed file identity is re-parsed and reported as new
- `search` is FTS5 `MATCH`; `get` returns fixture literals including account + placement

**ReadAPI** (wraps the index; MCP will wrap this later)

- `list` / `search`: cursor pages, default 25, hard max 100; every hit shows account + placement
- `listPlacements`: account + mailbox stem
- `get`: partial messages searchable and marked; empty body is `ReadBody.notAvailable`

Ingest is the on-open sweep. FSEvents stays a later caller. YAGNI held: no GrantGate, no MCP, no daemon.

## Comments

- 2026-08-19 — TDD MailboxIndex + ReadAPI on `feat/03-mailbox-index`. SQLite schema and FTS triggers are not seams.
