# 01 · Prototype Agent API settings UI

Type: prototype  
Status: claimed  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/32

## Question

What should Control Center look like when agents are user-defined endpoints (any number) with **name**, **optional icon**, and **MCP and/or CLI** — not fixed Cursor/Grok half-cards?

## Proto

`.scratch/mailgent-local-cli/examples/prototype-agent-api-settings.html`

```bash
open .scratch/mailgent-local-cli/examples/prototype-agent-api-settings.html
```

Flip `?variant=A|B|C` (or ← → / bottom bar). State dump at the footer updates live.

| Key | Structure |
|-----|-----------|
| A | Dynamic cards — compact by default; click card to expand MCP/CLI + actions; Add tile |
| B | List + inspector — left roster; right pane **View** (calls chart + stats + credential actions) / **Edit** (name, access, icon); Add = draft in edit mode |
| C | Channels-first sheet — compact roster; stepped Add (name → channels → icon) |

## Product lock

**Pending.** Flip A/B/C and record the winner (or mix) below. Swift work on the local-cli plan starts after this lock.

## Out of scope

- Real socket / Bearer / pairing.json
- Grant Desk / Access Log chrome
- Swift / `project.yml` changes
- Version bump

## Comments

### 2026-10-13

Proto scaffolded from plan `agent_api_settings_proto`. Shared model: in-memory agents, templates on Add (Cursor / Grok Bot / Blank), optional icon picker. **Enable local CLI** lives in app Settings (not Control Center header); proto keeps `cliEnabled` in the state dump only.

CLI copy examples updated to locked wire format (issue 02): UDS + credential + MCP `tools/call` JSON — no per-tool flags.

Equal card columns (`minmax(0, 1fr)`). Variant A cards are **compact by default**; click the summary row to expand MCP/CLI panels + Setup/Edit. Variant B right pane: **View** (14-day calls chart with This endpoint / All endpoints overlay, stats, issued-at, Copy Bearer / setup instructions, Setup, Revoke, Delete) vs **Edit** (name, MCP/CLI access, icon). **Setup agent…** wizard: intro → **credential** → MCP and/or CLI → done. Credential step: Pair + **Copy Bearer / token** into the agent’s own MCP config or `MAILGENT_TOKEN` (possession model; Keychain = MailGent vault only — no CLI auto-unlock by `--agent`). Instruction copies stay secret-free. See [03 · Credential handoff](03-credential-handoff.md) (locked). CLI examples collapse by default like MCP.
