# Handoff: MCP `open_in_mail` — open a message in Apple Mail

**Status:** ready to implement  
**Repo:** `/Users/marotron/dev/MailGent`  
**Requested:** 2026-10-06 (agent workflow: after MailGent find, surface message in Mail.app for human reply)  
**Suggested branch:** `feat/mcp-open-in-mail`  
**Suggested version:** **0.10.0** (new MCP tool → MINOR; follow `.cursor/rules/versioning.mdc`)  
**Depends on:** **0.9.0** already shipped `mailURL` + `internetMessageID` on MCP `get` (do not re-implement that)

## Goal

Add an MCP tool **`open_in_mail`** that, given the same ids as `get` (`accountID`, `placement`, `id`), opens that message in **Apple Mail** from the **MailGent app process** (same path as Companion “Open in Apple Mail”).

Agents must not rely on handing the human a clickable `message://` link. Cursor chat often does not launch custom URL schemes; agent-shell `open` also fails. The working path is `NSWorkspace.shared.open(url)` inside MailGent.

## Why (product)

| Approach | Result in practice |
|----------|-------------------|
| Return `mailURL` on `get` for human to click | Cursor / chat often no-ops custom schemes |
| Agent runs `open 'message://…'` | Launch Services / sandbox often fails (`kLSExecutableIncorrectFormat`, `Unable to find application named 'Mail'`) |
| Companion UI “Open in Apple Mail” | Works via `NSWorkspace` in MailGent |
| **MCP `open_in_mail`** | Same as Companion, triggered by agent when user asks to open/reply |

Keep `mailURL` on `get` as metadata / debug. **`open_in_mail` is the action.**

## Already implemented (reuse; do not reinvent)

| Piece | Location |
|-------|----------|
| RFC Message-ID on full load | `ReadMessage.internetMessageID` via `gateway.get` |
| URL builder | `AppleMailHandoff.messageURL(internetMessageID:)` in `MailStore/Sources/MailStore.swift` → `message://%3C…%3E` or `nil` |
| UI open | `CompanionSession.openInMail(accountID:placement:id:)` → load → `NSWorkspace.shared.open(url)` |
| MCP `get` payload | `AuditJSON.messageDetail` already includes `mailURL` / `internetMessageID` when present (0.9.0) |
| Injectable host pattern | `LoopbackHost` already holds optional `IndexUpdating` / `MailSourceControlling` — mirror that for an opener |

## Architecture constraint

`LoopbackMCPServer` / `MailStore` are **Foundation-only** (no AppKit). Do **not** import AppKit into MailStore.

Inject an opener on `LoopbackHost`, implemented by the app (AppKit), same style as `setSourceController` / `setGateway`.

Suggested protocol (name freely if a better fit exists):

```swift
public protocol AppleMailOpening: Sendable {
    /// Opens the message in Apple Mail. Returns false if URL cannot be opened.
    func openMessage(internetMessageID: String) -> Bool
}
```

App-side adapter (sketch):

```swift
final class WorkspaceAppleMailOpener: AppleMailOpening, @unchecked Sendable {
    func openMessage(internetMessageID: String) -> Bool {
        guard let url = AppleMailHandoff.messageURL(internetMessageID: internetMessageID) else {
            return false
        }
        // Prefer MainActor / main queue if NSWorkspace requires it in practice.
        return NSWorkspace.shared.open(url)
    }
}
```

Wire in `AgentBridge.makeLoopbackHost()` (or wherever gateway/source controller is set):  
`host.setAppleMailOpener(WorkspaceAppleMailOpener())` (or equivalent setter).

Tests: inject a fake opener that records the Message-ID and returns `true`/`false`.

## Spec (do this)

### 1. MCP tool `open_in_mail`

**Name:** `open_in_mail` (snake_case; accept camelCase alias `openInMail` in `callTool` if other tools do — `list_new` / `listNew` pattern).

**Input** (same as `get`):

| Arg | Type | Required |
|-----|------|----------|
| `accountID` | string | yes |
| `placement` | string | yes |
| `id` | string | yes |

**Behaviour:**

1. Require gateway (same as other read tools) — fail `indexNotReady` if unbound.
2. Authenticate / grant: call **`gateway.get(...)`** with the same credential and ids (reuses Scope + leak-guard envelope access). Do **not** invent a bypass that skips `get`.
3. If `internetMessageID` empty after trim → error (do not invent URL from numeric `id`).
4. If opener not bound → clear error (e.g. opener unavailable / not running in app host).
5. Call opener with Message-ID. If `open` returns false → error.
6. Return JSON success payload (below).
7. Append Access Log entry (new `AuditKind`).

**Success JSON** (suggested):

```json
{
  "opened": true,
  "accountID": "…",
  "placement": "INBOX",
  "id": "389299",
  "internetMessageID": "<…@…>",
  "mailURL": "message://%3C…%3E"
}
```

**Errors** (clear MCP error strings, fail closed):

- Missing / bad arguments
- Out of scope / not granted (whatever `get` already throws)
- No Message-ID
- Opener not configured
- `NSWorkspace.open` returned false

### 2. Grants / privacy

- Same as `get` for message existence and Scope.
- Opening does **not** require body grant (envelope / Message-ID is enough). If current `get` withholds the whole message when out of Scope, that remains correct — do not open what the agent cannot `get`.
- Do **not** open arbitrary Message-IDs passed by the agent without resolving through granted `accountID`/`placement`/`id`.

### 3. Audit

- Add `AuditKind` case, e.g. `openInMail = "open_in_mail"`.
- Log request summary (accountID, placement, id) and response (`opened`, mailURL or error).
- Access Log UI should show the kind sensibly (follow existing kind display patterns; no new Companion button required).

### 4. Tool descriptor

Add to `makeToolDescriptors()` with description like:

> Open a granted message in Apple Mail on this Mac (same as Companion Open in Apple Mail). Use after search/list when the human needs to reply or view that exact message. Args match get. Does not send mail or create a draft. Fails if the message has no RFC Message-ID.

### 5. Tests

- Fake opener + in-memory gateway: happy path returns `opened: true` and expected `mailURL`.
- Message without Message-ID → tool error; opener never called.
- Opener unset → tool error.
- Opener returns false → tool error.
- Existing MCP / `AppleMailHandoff` tests stay green.

Prefer unit tests in `LoopbackMCPServerTests` (pattern already uses `LoopbackHost` + gateway).

### 6. Docs / version closeout

Same turn as the bump (do **not** commit until user confirms):

- `CHANGELOG.md` → `### Added` under new `## [0.10.0]`
- Sync versions per `.cursor/rules/versioning.mdc` (`project.yml` MARKETING_VERSION, README, PRIVACY if it lists tools, MCP `serverInfo.version` in `LoopbackMCPServer`, build number, xcodegen)
- Print Version closeout block; wait for user before stage/commit/tag

### 7. Optional polish (only if trivial)

- Companion could call the same opener type as MCP (dedupe `CompanionSession.openInMail` → shared opener). Nice-to-have; not required for acceptance.
- Update Personal vault MailGent rule / skill only if this repo owns that doc — otherwise leave Personal vault alone unless user asks.

## Out of scope

- Yahoo / Gmail **web** links
- Auto-reply / paste draft body into Mail
- Selecting message via AppleScript mailbox walk (Message-ID URL is the supported path; do not add Scripting Bridge unless `message://` proves broken **from MailGent’s** `NSWorkspace.open` — verify that first; Companion already uses it)
- Adding `mailURL` to search/list
- Re-doing 0.9.0 `get` fields

## Acceptance checklist

- [ ] MCP `tools/list` includes `open_in_mail`
- [ ] Agent calls `open_in_mail` with ids from `search`/`get` → Apple Mail comes forward on that message (manual smoke on a real Hyperoptic / any inbox mail with Message-ID)
- [ ] Out-of-scope id fails like `get` (no open)
- [ ] Missing Message-ID fails; no fake URL
- [ ] Access Log shows `open_in_mail` entry
- [ ] `make test` green
- [ ] Version **0.10.0** + CHANGELOG updated together; no commit until user OK

## Context trigger (product)

During `/mailsync` Hyperoptic cancel (`01-house/00-past/01-B138RJ`), agent found Yahoo ids `389299` / `389407` and returned `mailURL` from `get`. Human click and agent `open` both failed. Companion Open already worked. User asked for MCP call that opens the mail.

Related (shipped): `docs/agents/handoff-mcp-get-mail-url.md` → implemented in **0.9.0**. This handoff is the follow-up action tool.

## Kickoff prompt (paste for next agent)

```
Implement MailGent MCP open_in_mail. Follow: /Users/marotron/dev/MailGent/docs/agents/handoff-mcp-open-in-mail.md
Repo: /Users/marotron/dev/MailGent — branch feat/mcp-open-in-mail — target 0.10.0. Do not commit until I confirm.
```

## Do not

- Import AppKit into MailStore
- Build URL from MailGent numeric `id` / `.emlx` path alone
- Open Message-IDs that did not come from a granted `get`
- Land on `main` without `feat/…` branch
- Commit or tag without explicit user confirmation
