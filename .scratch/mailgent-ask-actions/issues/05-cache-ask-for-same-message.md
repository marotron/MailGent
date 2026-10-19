# 05 · Cache Ask for same agent + message

Type: research  
Status: open  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/41

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

## Comments

### 2026-10-17

Filed from chat; mirrored to GitHub [#41](https://github.com/marotron/MailGent/issues/41) (`enhancement`, `roadmap`, `fog`, `next-version`).

### 2026-10-17 (Settings + share scope)

User lock-in: Settings toggle + validity time; default per-agent isolation; optional All / Selected agents sharing. Updated [#41](https://github.com/marotron/MailGent/issues/41).
