# 05 · Cache Ask for same agent + message

Type: research  
Status: shipped in 0.13.0 (Selected agents share deferred)  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/41

## Proto

```bash
open .scratch/mailgent-ask-actions/examples/prototype-ask-cache.html
```

Logic demo (buttons, not a Settings screen). Allow / Block, `get` again as Cursor MCP, Cursor CLI, then Grok. Add Body as Ask. Save a Pass rule for Subject. Save a Block rule for Body. Forget Cursor. Allow with redact does not cache Body.

State dump: grants, rules, enablements, cache entries per field, last prompt, last tool result.

## Question

After the user Allows or Blocks an Ask for a message, should follow-up `get`s skip the dialog for a short validity window — with Settings to enable it, set TTL, and choose who shares the cache?

## Context

- Today full-field Ask on `get` prompts every time (“human decision each time”).
- `AttachmentContentAskCache` already remembers Attachment Content Ask per agent + message until restart.
- Agents often re-`get` the same email during a conversation.

## Product sketch

- Short-lived cache, not a standing grant (Grant Desk On / Rules-from-Ask stay the “always” path).
- **Settings:** enable/disable; validity duration; share scope.
- **Default share scope: per agent** — agent B does not reuse agent A’s decision.
- Optional share: **all agents**, or **selected agents** that share the cache pool.
- Message key: account + placement + message id; agent (or pool) from share scope.
- Remaining fog (defaults, Selected UX, access-log marking) → [#41](https://github.com/marotron/MailGent/issues/41).

## Shared seams

Ship in any order with [#21](https://github.com/marotron/MailGent/issues/21), [#22](https://github.com/marotron/MailGent/issues/22), and [#32](https://github.com/marotron/MailGent/issues/32). Do not close these off:

- Key on pairing `agentID` ([#31](https://github.com/marotron/MailGent/issues/31)), not display name and not MCP vs CLI. One endpoint’s two channels share one cache. Another endpoint is another id.
- Store **per field**, not one bit for the whole dialog. A field that was not in the earlier prompt still asks.
- Consult the cache only after Scope + Pass/Block overlays. A field a rule sets On or Off never reads the cache.
- Rule save ([#21](https://github.com/marotron/MailGent/issues/21)) does not write this cache. A later `get` of the same message follows the rule because overlays run first.
- Entry shape can later hold an optional redacted body ([#22](https://github.com/marotron/MailGent/issues/22)). A plain Allow must not skip a future redact.
- All / Selected sharing, if added, is a lookup policy over per-agent entries, not a second store. [#35](https://github.com/marotron/MailGent/issues/35) must not copy cache entries.

## Comments

### 2026-10-17

Filed from chat; mirrored to GitHub [#41](https://github.com/marotron/MailGent/issues/41) (`enhancement`, `roadmap`, `fog`, `next-version`).

### 2026-10-17 (Settings + share scope)

User lock-in: Settings toggle + validity time; default per-agent isolation; optional All / Selected agents sharing. Updated [#41](https://github.com/marotron/MailGent/issues/41).
