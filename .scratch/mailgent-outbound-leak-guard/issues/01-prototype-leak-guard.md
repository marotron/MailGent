# Prototype Outbound Leak Guard

Type: prototype
Status: claimed
Branch: `proto/outbound-leak-guard`

## Question

Can users configure built-in secret detection, custom literal/wildcard/regex filters, and redact-vs-replace actions on an allowlisted mailbox scope — with clear separation from grant denial — before we wire MailStore?

## Surface

Single interactive HTML prototype:

`examples/prototype-outbound-leak-guard.html`

Variants exercised on one page (no `?variant=` split):

1. **Grant desk · Scope** — placements + grant field badges + **🛡 scan** per allowed row (leak-guard opt-in)
2. **Grant desk · Access** — per-placement caps; preview follows selected asset
3. **Grant desk · Privacy** — master toggle, built-in class checklist, custom rule editor, subject/body hit mode
2. **Live preview** — editable sample subject/body → agent payload + MCP JSON
3. **Access log mock** — grant denied (red hatch) vs autodetect withheld (amber) vs sanitized spans (amber badge + hover original)

JS detection mirrors planned v1 heuristics (no Core ML).

## Out of scope

- Real MailStore / AgentReadAPI integration
- Persistence to `sensitive-filter.json`
- Performance budget / serial queue

## Comments

- 2026-08-31 — Claimed on `proto/outbound-leak-guard`. HTML + in-browser rule engine for HITL before `feat/outbound-leak-guard`.
