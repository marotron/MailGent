# Draft Ledger Seam + MCP

Type: task
Status: claimed
Blocked by: 06

## Question

Can a MailGent-owned **DraftLedger** (create / update / list versions / copy body) land on the local-read train with thin MCP `create_draft` / `update_draft`, without Mail-store writes or send?

## Context

**Branch:** `feat/07-draft-ledger` off the ticket-05 tip (same lineage as `feat/05-mcp-read`). Prototype primary source: `proto/draft-outbound` on [06](06-draft-outbound.md).

Ticket 06 picked **B**. Build the real seam with TDD, then wrap for agents:

- **DraftLedger** — versioned drafts in process memory (persist later only if needed); operations: create, update (new version), list versions, copy (return body for clipboard / agent).
- **MCP** — `create_draft` / `update_draft` on the existing loopback server; auth same as read tools.
- Still **no** Apple Mail store writes, AppleScript, `mailto:`, send, or mutation approvals.

## Verify

`make test` green. Ledger create → update → list → copy body round-trips in unit tests. Authenticated MCP `create_draft` / `update_draft` return version payloads; unauthenticated calls fail closed.

YAGNI: no rich text, no persistence, no send, no Mail.app scripting, no approval queue.

## Inputs

- [06 · Draft Outbound Prototype](06-draft-outbound.md) — B wins; proto on `proto/draft-outbound`
- [05 · MCP Read, Pairing, Grants, Audit](05-mcp-pairing-grants-audit.md)
