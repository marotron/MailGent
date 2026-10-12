# 02 · Manual redact then Allow

Type: task  
Status: open  
Blocked by: 01  
GitHub: https://github.com/marotron/MailGent/issues/22

## Question

How should the Ask body preview let a human redact selected spans before Allow, returning a one-shot body override for this `get` only?

## Product lock (spec only until 01 ships or parks)

See [`../spec.md`](../spec.md). Highlights:

- Select span(s) on Body preview → replace with fixed mask (e.g. `[redacted]`)
- Allow returns optional redacted body for this `get` only
- Leak guard still runs after the override
- No persistent leak-guard / custom filter unless a later “save as custom filter” ask

## Seams (Phase 3 — not yet)

1. Extend `ConditionalAccessDecision` (or parallel payload) with optional redacted body
2. Apply override in `AgentReadAPI.get` after Allow, before/around `sanitizeGet`
3. Selection UI on Ask body preview
4. Access log: keep original locally if that matches existing leak-guard privacy posture

## Out of scope

- Teaching the agent new MCP tools for redaction
- Auto-saving redactions as leak-guard custom filters

## Comments

### 2026-10-12

Mirrored to GitHub [#22](https://github.com/marotron/MailGent/issues/22) (`enhancement`, `roadmap`, `next-version`). Blocked by [#21](https://github.com/marotron/MailGent/issues/21).
