# 04 · Grok Bot MCP HTTP connection intermittent

Type: observation  
Status: resolved  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/34

## Summary

2026-10-14: Grok Bot failed to connect to MailGent’s loopback MCP endpoint (`http://127.0.0.1:8788/mcp`) using an `mcpServers` config with `Authorization: Bearer …`. 2026-10-15: the same config connected and tools responded without any MailGent-side change.

A chat fragment from Grok Bot initially suggested **Grok may run in a remote execution environment that refuses local-only MCP servers outright**, error: *“This MCP server can only run in local environments.”* However, Grok Bot later confirmed the actual cause was a **stale token plus missing mailbox grants**, not a client update or remote-execution gating. The local-only message appears to have been a misleading surface explanation.

## Config (redacted)

```json
{
  "mcpServers": {
    "mailgent": {
      "url": "http://127.0.0.1:8788/mcp",
      "headers": {
        "Authorization": "Bearer ••••"
      }
    }
  }
}
```

## What we know

- MailGent loopback server was running on `127.0.0.1:8788`.
- Cursor on the same machine/endpoint continued to work during the failure window.
- No MailGent version bump or config change between failure and success.
- Today Grok initializes, lists tools, and calls them.
- Grok Bot chat fragment initially said its connection service **refuses local-only servers outright**; the UI showed *“needs sign-in”*.
- Grok Bot later confirmed the failure was caused by a **stale token plus missing mailbox grants**, not remote execution.
- Separately, MailGent’s last sync for a third-party inbox used in the workflow was two days prior (Oct 10), so even a successful connection may not have returned the requested email until a fresh sync ran.

## Hypotheses

1. **Stale token plus missing mailbox grants.** Confirmed by Grok Bot. *(leading)*
2. **Grok Bot sometimes executes remotely and blocks 127.0.0.1 MCP endpoints.** Consistent with the earlier chat fragment, but Grok Bot later ruled this out. *(rejected)*
3. **Grok Bot has a local-execution path** that allows `127.0.0.1` to work, and which path is hit is non-deterministic. *(rejected)*
4. **“Needs sign-in” UI is misleading** for local-only failures; the real failure was stale auth / grants, not the address itself.
5. Environmental (port conflict, local firewall) — less likely because the failure message described was specifically about local-only servers.

## Notes

MailGent’s loopback server currently accepts **POST /mcp** only and returns `405` for **GET /mcp**. If a client expects SSE-style MCP (GET stream), it will see a method-not-allowed response. This is worth confirming when the issue recurs.

## Next time it happens

- Check MailGent Access Log: any request entry (or total absence) tells us whether the client reached MailGent.
- Check Grok Bot logs/error panel for the exact failure message.
- Try a manual `curl` POST to `http://127.0.0.1:8788/mcp` with an `initialize` JSON-RPC body.
- Record Grok Bot version/build date.
- Compare with Cursor behavior on the same endpoint.
- Ask Grok Bot explicitly whether it is running locally or remotely; the connection service restriction may depend on execution context.

## Out of scope

No code change unless a reproducible server-side cause is found. A remote-reachable MailGent endpoint would bypass this, but that is a separate product/security decision (not tracked here).

## Comments

### 2026-10-15

Logged from user report. Connection currently working; treat as a client-compatibility watch item.

### 2026-10-15 · Grok Bot chat fragment

Screenshot: [04-grok-chat-fragment.png](assets/04-grok-chat-fragment.png)

Key points from the fragment:

- Grok Bot explained the failure as: *“This MCP server can only run in local environments.”*
- The bot’s connection service refuses local-only servers outright because the bot runs on a remote computer.
- The workflow that broke was retrieving an 8-character code from a Greenhouse email to fill a Geotab form.
- MailGent sync for the relevant inbox was noted as “partly broken” (last sync Oct 10).
- Bot-proposed fixes:
  1. Use MailGent’s command-line tool on the user’s Mac (manual approval per run, bypasses access checks).
  2. Re-register MailGent as a remote connection reachable over a URL.

These proposals are recorded for context; neither is being implemented without a dedicated decision.

### 2026-10-15 · Version confirmation

User confirmed the recent Grok Bot build **0.70.2** works with MailGent **v0.11.3** on the same `http://127.0.0.1:8788/mcp` endpoint. This rules out a blanket incompatibility between those versions.

### 2026-10-15 · Root cause from Grok Bot

Grok Bot confirmed:

- Actual cause: **stale token plus missing mailbox grants**.
- Not a Grok Bot update or remote-execution gating.
- CLI and extra endpoints are noted as postponed future work.

## Answer

The intermittent connection was caused by **stale authentication plus missing mailbox grants**, not by Grok Bot’s MCP client or a remote/local execution split. No MailGent code change is needed. If the symptom recurs, check the token and grant scope first; the “local environments” message was a misleading surface explanation.

Status → **resolved**.
