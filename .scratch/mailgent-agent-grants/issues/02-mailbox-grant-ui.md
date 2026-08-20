# Companion Mailbox Grant UI

Type: task
Status: resolved
Blocked by: 01

## Question

Can a human in the companion pick which accounts and mailboxes a paired agent may read, without leaving the control center?

## Context

**Branch:** `feat/01-persist-grants` (continues on same branch through 02; split later if PR size bites).

Control-center card: list placements from the open index/catalog; toggles for account-wide vs per-mailbox allow; save → `GrantGate` + persist (01). Show effective summary next to the paired agent.

## Verify

Toggle INBOX only → agent search hits only that mailbox; Archive omitted. Uncheck all → empty results. Survives relaunch via 01.

YAGNI: no participant/date; no deny rows; no full grant desk IA yet.

## Inputs

- [01 · Persist grants](01-persist-grants.md)
- Product [10 · Policy authoring](../mailgent-product-definition/issues/10-prototype-policy-authoring.md) — scope step account → placement

## Answer

Yes. Companion **Agent may read** checkbox tree on the paired-agent card:

- Account-wide allow (all mailboxes) or per-mailbox allows
- Narrowing from account-wide → one mailbox via mailbox toggle
- Clear all grants; empty grants warn that agent search stays empty
- `grantRevision` drives SwiftUI refresh; persists via 01

## Comments

- 2026-08-20 — Claimed and implemented on `feat/01-persist-grants`; `make test` green.
