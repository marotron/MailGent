# MCP Read, Pairing, Grants, Audit

Type: task
Status: resolved
Blocked by: 04

## Question

Can a paired `machine-local` agent over hardened loopback MCP list/search/get only granted Apple Mail, with unauthorized calls failing closed and every search recorded in an append-only audit the companion can inspect?

## Context

**Branches:** `feat/05-mcp-read` then `feat/06-pairing-grants-audit` (split if PRs get large) off `train/local-read`.

MailGent is the MCP **server**. Product owns policy; MCP is wire only. First ship: hardened loopback HTTP. Context7: current MCP spec + Swift MCP SDK (or a thin Streamable HTTP JSON-RPC server if the SDK is a poor fit).

Vertical slices:

1. **ReadAPI** over HTTP loopback: `list` / `search` / `get` / `listPlacements` with no auth → reject.
2. **Pairing:** wizard subset of product ticket 17 Variant A — name, `machine-local`, credential, Cursor config snippet, wait-for-connect. Proof of possession on every call.
3. **GrantGate:** at least one account (snapshot, not “all future accounts”); optional mailbox; deny wins; counts omit denied.
4. **AuditLog:** pair, search, get, revoke; inspect in companion; Touch ID purge can wait if it blocks the train.
5. Cursor (or another MCP host) can list/search a fixture mailbox end-to-end.

Reuse existing HTML pairing prototype as the visual reference; do not rebuild three web variants unless the Swift pairing UI is genuinely unclear — then a short SwiftUI proto, same switcher rule, then HITL.

This is the **first-ship acceptance slice**: a power user grants FDA, pairs Cursor, searches/reads Apple Mail through MailGent, and sees an access log.

## Verify

Unauthorized call fails; granted agent sees only allowed mail; audit contains the search; revoke stops access immediately.

YAGNI: no UDS/App Group required; no stdio; no remote relay; no mutation tools; no draft tools.

## Answer

**Yes.** Hardened loopback MCP on `127.0.0.1:8787` serves Cursor (Streamable HTTP JSON-RPC). Thin server (`LoopbackHTTPListener` + `LoopbackMCPServer`) — no Swift MCP SDK. Policy stays in MailStore: `Pairing`, `GrantGate`, `AuditLog`, `AgentReadAPI`.

### Verified (2026-08-20)

| Check | Result |
| --- | --- |
| No / bad Bearer | `401 unauthorized` |
| Cursor `initialize` / `tools/list` / `tools/call` | Works |
| `list` / `search` / `listPlacements` / `get` | Works; list/search return `items` with `accountID` / `placement` / `id` so `get` is callable |
| Audit | Companion Access log + `AuditLog` entries for pair/search/get/revoke |
| Revoke | Clears pairing; old Bearer fails closed; re-pair issues new credential |
| Persistence | Pairing survives relaunch (`~/Library/Application Support/MailGent/pairing.json`); companion syncs Bearer into `~/.cursor/mcp.json` |

Grants: account-level snapshot on catalog sync (deny-by-default). Per-mailbox grant UI left as polish — `GrantGate` already supports mailbox allows.

## Comments

- 2026-08-20 — Claimed on `feat/05-mcp-read`. Policy seams landed under MailStore TDD:
  - `Pairing` (hashed credential, revoke, fail-closed)
  - `GrantGate` (deny-by-default; account ± mailbox allow)
  - `AuditLog` (pair/search/get/revoke; inspect via API)
  - `AgentReadAPI` wraps ReadAPI with auth + grant filter + audit
  - `LoopbackMCPServer` thin JSON-RPC `tools/call` for search/list/get/listPlacements (401 without Bearer)
  - Companion `AgentBridge` + control-center card: pair Cursor, Cursor config snippet, access log
  - Still open: real `127.0.0.1` NWListener bind, Swift MCP SDK / Streamable HTTP session, grant mailbox UI, Cursor host E2E
- 2026-08-20 — Loopback HTTP bind landed (`LoopbackHTTPListener` → `127.0.0.1:8787`). MCP handler now covers Cursor handshake: `initialize`, `notifications/initialized`, `tools/list`, `tools/call`. Companion binds after index open/rebuild. Still open: grant mailbox UI polish, full Cursor host E2E confirmation after app relaunch + fresh Bearer snippet.
- 2026-08-20 — Cursor E2E confirmed (fixture + earlier live mail). Enriched list/search payloads; pairing persistence + auto-sync of Cursor `mcp.json` Bearer. Ticket resolved.
