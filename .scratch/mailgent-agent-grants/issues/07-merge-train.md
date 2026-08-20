# Merge Agent-Grants Train

Type: task
Status: resolved
Blocked by: 06

## Question

Is `train/agent-grants` ready to merge to `main` so humans can author durable agent data grants on the shipped local-read companion?

## Context

Merge when 01–06 are green. Update local-read map fog. Do not start OAuth on this PR.

## Verify

Train on `main`; `make test` green; auto-all-accounts gone; desk usable for account/mailbox/selector/deny/fields.

YAGNI: no OAuth work.

## Inputs

- Tickets 01–06

## Answer

Yes. `train/agent-grants` fast-forwarded onto the stacked feat tip (`7cfbd69`) and merged to `main`. Durable per-agent data grants + lean Scope/Access desk are on `main`.

- `make test` green (`** TEST SUCCEEDED **`).
- Auto-all accounts already removed on ticket 01; pairing starts with zero grants.
- OAuth not started; next train remains `train/oauth` with local-read kept as a source.

## Comments

- 2026-08-20 — Claimed; FF `feat/01-persist-grants` → `train/agent-grants` → `main`; `make test` green.
- 2026-08-20 — Resolved. Agent grant authoring on `main`.
