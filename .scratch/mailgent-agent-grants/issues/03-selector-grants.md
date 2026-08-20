# Participant and Date Selectors

Type: task
Status: resolved
Blocked by: 02

## Question

Can `GrantGate` narrow allows by participant (From/To/Any) and inclusive date range / rolling window using indexed message fields, without leaking denied mail in search?

## Context

**Branch:** `feat/01-persist-grants` (stacked).

Extend grant model (TDD): optional address/domain selectors (normalized; role-aware From/To; Any participant) and date bounds (provider `date` on `IndexedMessage`). Different selector groups AND; values within a group OR. Account still required.

Companion UI: minimal controls on the mailbox card or a small “Narrow” section — full desk is ticket 06.

## Verify

Allow account + From `a@example.com` → only matching messages. Date window excludes older mail. Search/list/get stay deny-filtered.

YAGNI: no smart folders yet unless trivial; no Cc/Bcc until indexed; no timezone UI polish beyond local parse of stored dates.

## Inputs

- [07 · Agent authorization](../mailgent-product-definition/issues/07-define-agent-authorization.md) — address/date rules
- [02 · Mailbox grant UI](02-mailbox-grant-ui.md)

## Answer

Yes.

- `GrantParticipant` (from/to/anyParticipant) + `dateStart`/`dateEnd` on `Grant`; OR within participants, AND across groups.
- `GrantGate.allows(IndexedMessage)` used for list/search filter; `get` re-checks after load.
- Minimal companion fields: Narrow From + on/after ISO8601 applied to next checkbox allow.
- JSON decode tolerates older grants without selector keys.

## Comments

- 2026-08-20 — Claimed; TDD + minimal Narrow UI; `make test` green.
