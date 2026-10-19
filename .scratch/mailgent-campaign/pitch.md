# MailGent → pitch and campaign copy

Candidate copy for the GitHub README, the repo "About" box, a landing page, and launch posts. Interactive demo: [`demo.html`](demo.html) (open it in a browser; it needs `assets/mailgent-icon.png` next to it).

Everything below matches **0.8.2 alpha**. Before you reuse a line, check it against the [claims checklist](#claims-checklist).

---

## Positioning

**Category:** a permission layer between your email and AI agents, running on your Mac.

**Audience (first):** Mac users who already use an AI agent (Cursor, Grok) and keep their mail in Apple Mail. **Later:** anyone who wants AI help with email but doesn't want to hand over the whole inbox.

**Core promise:** your agent gets your slice of the inbox, never the whole thing, and you can see every request it made.

## Taglines (pick one)

1. Let AI help with your email. Without handing over your inbox.
2. Your inbox, on a need-to-know basis.
3. Give your AI agent a slice of your inbox, not the keys.
4. The gatekeeper between Apple Mail and your AI.
5. Agent-safe email for Apple Mail.

## One-liner (GitHub "About" box, ≤ 350 chars)

> macOS menu-bar companion for Apple Mail that lets AI agents (Cursor, Grok) search and read only the mail you allow, redacts secrets on-device, and logs every request. No cloud, no built-in AI. Alpha.

**Suggested topics:** `macos` `apple-mail` `mcp` `model-context-protocol` `ai-agents` `privacy` `email` `swift` `swiftui` `menu-bar-app`

## Elevator pitch

**~50 words.** MailGent sits in your Mac's menu bar beside Apple Mail. When an AI agent wants to help with your email, MailGent hands it only the mailboxes, senders and fields you've allowed, hides passwords and API keys first, and logs exactly what it shared. Everything runs on your Mac, and revoking access takes one click.

**~100 words.** AI agents are good at email: finding the flight confirmation, listing unpaid bills, drafting replies. But connecting one usually means giving it everything: every message, every attachment, every year, with no record of what it read. MailGent changes that. It's a small macOS companion for Apple Mail that acts as a gatekeeper. You choose which mailboxes, senders, dates and fields each agent can see. A leak guard redacts secrets on your Mac before anything leaves. Agents can draft, but can't send or delete. And an Access Log shows every request exactly as the agent received it. No MailGent cloud, no built-in AI.

## README block: "Why MailGent" (drop in under the title)

```markdown
**Let AI help with your email — without handing over your inbox.**

MailGent is a menu-bar companion for Apple Mail. Your AI agent (Cursor, Grok Bot) asks MailGent instead of reading your mailbox directly, and gets only what you allowed:

- **Share a slice, not the inbox** — pick mailboxes, senders, date ranges and fields (headers, text, attachments). New agents start with nothing.
- **Secrets stay home** — the on-device leak guard redacts API keys, tokens and password lines before mail leaves your Mac.
- **A receipt for every request** — the Access Log shows each search, read and draft exactly as the agent received it.
- **Drafts, never sends** — agents can write drafts inside MailGent; this alpha cannot send, move or delete mail, and never writes to Apple Mail.
- **Your Mac, your agent** — no MailGent server, no built-in AI, loopback-only connection, one-click revoke.
```

## Three-beat story (slides, video, landing hero)

1. **The problem.** "You wanted help with this week's bills. Your agent got your bank statements, medical letters and family email too."
2. **The turn.** "MailGent sits between Apple Mail and your AI. It shares your slice, hides your secrets, and keeps the receipts."
3. **The proof.** Demo: flip "Personal" off → ask "What's my bank balance?" → the agent can't see it. Turn leak guard off → ask about work email → the deploy key leaks (red). Turn it back on → `[REDACTED:apiKeys]`.

## Short demo script (≈ 60 seconds, record from `demo.html` or the app)

| Time | On screen | Voice-over |
|---|---|---|
| 0–8s | Menu-bar dropdown | "This is MailGent. It lives next to Apple Mail." |
| 8–20s | Ask "What bills do I need to pay?" | "My agent asks MailGent, and gets only the Bills mailbox I shared." |
| 20–32s | Switch to "Headers only", ask again | "Headers only? It sees the senders but can't read the amounts." |
| 32–44s | Leak guard off → work question → red key; on → redacted | "Old credentials in email? The leak guard hides them before they leave my Mac." |
| 44–54s | Access Log rows | "And every request is here, exactly as the agent received it." |
| 54–60s | Revoke → ask again → refused | "One click, and the agent is out." |

## Launch posts

**Show HN**

> **Show HN: MailGent – let AI agents read only the email you allow (macOS, Apple Mail)**
>
> I wanted Cursor to help with my email without giving it my whole mailbox. MailGent is a menu-bar app that indexes Apple Mail locally and exposes it to agents over MCP on 127.0.0.1, through per-agent grants (mailbox, sender, date, field caps), Pass/Block rules, and an on-device leak guard that redacts keys and passwords. Every call lands in an access log with the exact response. Agents can draft but not send; it never writes to Apple Mail. Swift, Apache-2.0, early alpha. Feedback very welcome, especially on the permission model.

**X / Bluesky**

> Your AI agent doesn't need your whole inbox.
> MailGent (macOS, Apple Mail) shares only the mailboxes you choose, redacts secrets on your Mac, and logs every request. Free, open source, alpha. → github.com/marotron/MailGent

**LinkedIn**

> AI assistants are getting good at email, but connecting one is still all-or-nothing. I've been building MailGent, a small macOS companion for Apple Mail that works like a gatekeeper: you decide which mail each agent can see, secrets are redacted on-device before anything is shared, and every request is logged so you can check what the agent actually read. No cloud, no built-in AI, bring your own agent. It's an early, open-source alpha. I'd love feedback from people who use AI agents day to day.

## Say / don't say

| Say | Don't say (not true in 0.8.2) |
|---|---|
| "Reads the mail Apple Mail has downloaded" | "Connects to Gmail / Yahoo" (planned) |
| "Agents can draft inside MailGent" | "Agents can send, archive or delete" |
| "Cursor and Grok Bot have built-in pairing" | "Works with any AI" / "ChatGPT / Claude" |
| "Runs on your Mac, no MailGent server" | "End-to-end encrypted" / "zero-knowledge" |
| "Early alpha, provided as is" | "Secure", "safe", "bank-grade" |
| "Once shared, the agent's own privacy policy applies" | "Your data never leaves your Mac" (granted mail does go to the agent) |
| "Download from GitHub Releases" | "Notarized", "on the Mac App Store", "brew install" |
| "Drafts disappear when MailGent quits" (if asked) | "Approval queue", "Touch ID" |

## Claims checklist

Each campaign claim and where it lives in code. Re-check this table before every release.

| Claim | Source |
|---|---|
| Reads Apple Mail locally (`~/Library/Mail`), never writes it | `MailStore/Sources/MailStore.swift`, README "Warranty" |
| Private full-text search index on the Mac | `MailStore/Sources/MailboxIndex.swift` (SQLite FTS, `live-mail.sqlite` in Application Support) |
| Loopback only (this Mac) | `LoopbackHTTPListener.swift` binds `127.0.0.1` |
| Each agent has its own key; revoke = refused | `Pairing.swift` (SHA-256 hashed Bearer), `AgentBridge.pairAgent` / revoke |
| New agents see nothing until granted | `GrantGate.effectiveFields` returns nil with no allow |
| Mailboxes, senders/domains, dates, deny carve-outs | `Grant.matches`, `GrantGate` |
| Field caps: subject/from/to/cc/date, body, attachment info, attachment content | `GrantFields` |
| Pass / Block rules (From/Subject, When window) | `RuleEngine.applyOverlays` |
| Search/list return headers only | `LoopbackMCPServer` tool descriptions, `AuditJSON.page` |
| Leak guard on-device: API keys, JWT, password lines on by default; private keys, cards, SSN, phones, emails optional; custom literal/wildcard/regex; redact or withhold field | `BuiltInHeuristicDetector`, `OutboundLeakGuardPolicy.defaultBuiltInClasses`, `OutboundLeakGuard` |
| Leak guard must be switched on and opted in per mailbox | `OutboundLeakGuardPolicy` (`enabled: false`, empty `scopes`) |
| Attachments only when granted, 25 MiB cap | `AgentReadAPI.getAttachment` |
| Access Log stores exactly what the agent got | `LoopbackMCPServer` `audit.updateLast(responseSummary:)` |
| Agents can't send / move / delete; drafts are MailGent-only and in-memory | Tool list in `LoopbackMCPServer`; `DraftLedger` |
| Open in Apple Mail | `message://` handoff (`OpenInMailGlyph`, Companion Read, Access Log) |
| No built-in AI, no MailGent server | No network calls besides loopback listener |

## Assets

- App icon: `assets/mailgent-icon.png` (copied from `MailGent/Assets.xcassets/AppIcon.appiconset/icon_512x512.png`). Name and icon are trademarks. Forks rename.
- Screenshots to capture from the real app for the README: menu-bar dropdown, Grant Desk → Scope, Privacy tab, Access Log Formatted Response with a redacted span.
