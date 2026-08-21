# Field Exposure Caps

Type: task
Status: resolved
Blocked by: 04

## Question

Can a grant expose locator+envelope while omitting body and/or attachment content, with search only hitting readable fields and `get` omitting denied fields without redaction stubs?

## Context

**Branch:** `feat/01-persist-grants` (stacked).

## Answer

Yes for body/envelope on `get`.

- `GrantFields` on allow grants; `effectiveFields(for:agentID:)`
- `ReadMessage.omittingBody()` / `applying` → `.notGranted` (distinct from empty `.notAvailable`)
- MCP `get` returns `bodyAccess: "not_granted"` + agent-facing `note`, and **omits** `body` (never `""`)
- Companion **Allow body on next grant** checkbox
- Search may still FTS-match body text when body is off (known gap; field-aware search deferred)

## Comments

- 2026-08-20 — Resolved; body-off get covered by tests.
- 2026-08-21 — Superseded omission-without-hint for body caps: agents must distinguish grant denial from empty mail (`ReadBody.notGranted` + MCP `bodyAccess`).
