# Persist Grants, Stop Auto-All

Type: task
Status: resolved
Blocked by:

## Question

Can agent grants survive companion relaunch, and can we stop auto-allowing every detected account so deny-by-default is the real first-ship posture until the human picks mailboxes?

## Context

**Branch:** `feat/01-persist-grants` off `train/agent-grants`.

Today `AgentBridge.syncGrants(accountIDs:)` revokes and re-allows **all** catalog accounts on every sync. Pairing persists; grants do not.

- Persist grants beside pairing (`Application Support/MailGent/`).
- Remove auto-all behavior; pairing leaves the agent with **zero** grants until UI (ticket 02) adds them.
- Keep `GrantGate.allow(agentID:accountID:placement:)` as the public write API; add `list(agentID:)` / replace-or-clear helpers if tests need them.
- Restore grants on launch after pairing restore.

## Verify

`make test` green. Relaunch restores the same account±placement allows. Fresh pair → search returns empty until an allow is set. Catalog refresh does **not** invent new grants.

YAGNI: no selector/date/deny/fields yet; no grant desk UI.

## Inputs

- [05 · MCP pairing/grants](../mailgent-local-read-impl/issues/05-mcp-pairing-grants-audit.md)
- [07 · Agent authorization](../mailgent-product-definition/issues/07-define-agent-authorization.md) — account snapshot; new accounts never join automatically

## Answer

Yes on `feat/01-persist-grants`.

- `GrantGate.list` / `replaceAll`; `Grant` + `GrantSnapshot` Codable.
- `AgentBridge` persists `grants.json` beside pairing; restore on launch; fresh pair starts with zero grants.
- Removed `syncGrants(accountIDs:)` auto-all from catalog refresh and pair/revoke buttons.
- `allow` / `revokeGrant` / `clearGrants` for ticket 02 UI.

## Comments

- 2026-08-20 — Claimed; TDD list/replaceAll/JSON round-trip; wire AgentBridge persistence; strip auto-all.
- 2026-08-20 — Resolved; `make test` green.
