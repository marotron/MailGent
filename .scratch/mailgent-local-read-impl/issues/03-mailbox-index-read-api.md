# MailboxIndex and ReadAPI TDD

Type: task
Status: open
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
