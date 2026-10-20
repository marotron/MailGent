# 02 · Manual redact then Allow

Type: task  
Status: open  
Blocked by: 01  
GitHub: https://github.com/marotron/MailGent/issues/22

## Proto

```bash
open .scratch/mailgent-ask-actions/examples/prototype-ask-redact.html
```

Flip `?variant=` A/B/C. This `get` can return a masked body. `rules.json` stays put. **get again** prompts, because the cache has no body override yet.

## Question

How should the Ask body preview let a human redact selected spans before Allow, returning a one-shot body override for this `get` only?

## Product lock (spec only until 01 ships or parks)

See [`../spec.md`](../spec.md). Highlights:

- Select span(s) on Body preview → replace with fixed mask (e.g. `[redacted]`)
- Allow returns optional redacted body for this `get` only
- Leak guard still runs after the override
- No persistent leak-guard / custom filter unless a later “save as custom filter” ask

## Shared seams

Ship after [#21](https://github.com/marotron/MailGent/issues/21), and without blocking [#41](https://github.com/marotron/MailGent/issues/41) or [#32](https://github.com/marotron/MailGent/issues/32):

- Override is for this `get` only. It is not a `GrantRule` and not a standing grant.
- Ask cache entries ([#41](https://github.com/marotron/MailGent/issues/41)) must be able to carry an optional body override. Until that field exists, a cached plain Allow must not skip a redact prompt for Body.
- Same `agentID` for MCP and CLI ([#31](https://github.com/marotron/MailGent/issues/31) / [#32](https://github.com/marotron/MailGent/issues/32)). Another endpoint still gets its own Ask.

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
