# MCP Read, Pairing, Grants, Audit

Type: task
Status: open
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

## Inputs

- [04 · Companion Read UI Prototype Then Shell](04-companion-read-ui.md)
- Product tickets 04, 06, 07, 08, 17 (MCP wire, topology, authz, ops contract, pairing)
