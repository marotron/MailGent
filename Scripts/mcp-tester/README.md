# MailGent MCP tester

Local dogfood GUI for MailGent’s loopback MCP (`POST /mcp`). Tauri 2 + Vite + vanilla TypeScript. **Not** shipped in the MailGent DMG.

## Prerequisites

1. **Rust** (`rustc` / `cargo`) — [rustup](https://rustup.rs):

   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   source "$HOME/.cargo/env"
   ```

2. **Node** (npm) and Xcode Command Line Tools (same as MailGent builds).

## Run

```bash
cd Scripts/mcp-tester
npm install
npm run tauri dev
```

## Env

| Variable | Default | Use |
|---|---|---|
| `MAILGENT_BEARER` | _(empty)_ | Prefills Bearer; required against real MailGent |
| `MAILGENT_MCP_URL` | `http://127.0.0.1:8788/mcp` | Prefills URL |

Fake server (no real mail):

```bash
python3 Scripts/tests/await-ask/fake_mailgent.py --port 8798
# Connect to http://127.0.0.1:8798/mcp — any bearer
```

## Flow

1. Connect → `initialize` + `tools/list` (live tool list; no hardcoded allow-list).
2. Pick a tool → edit schema fields and/or Raw JSON → Call.
3. Soft timeout defaults: `await_ask` **25**, `await_propose_send` **60**. HTTP client budget is at least ~35s (soft + 10).
4. `list` / `search` / `list_new` render a hit list: **Get** fires `get` immediately; **Fill** only seeds args; **Open** calls `open_in_mail`. Double-click a row = Get.
5. Identicons on account / message / ask IDs (same seed → same face) so you can match the Ask dialog’s account prefix at a glance.
6. Shortcuts: Status · List · List new · Search… · Update · Await ask (last `askId`).
7. **Session export** (History pane): each call auto-saves to `Scripts/mcp-tester/exports/last-session.json`. **Export** also writes a stamped copy + copies JSON to the clipboard. **Copy log** copies only. Bearer is never written.

### Agent verification

Read `Scripts/mcp-tester/exports/last-session.json` after a dogfood run:

| Field | Meaning |
|---|---|
| `summary.verdict` | `PASS` / `FAIL` / `EMPTY` |
| `summary.ok` | `true` only when ≥1 call and zero failures |
| `summary.passed` / `failed` / `total` | counts |
| `calls[].ok` | per-call MCP success (`!isError` and no transport error) |
| `calls[].tool` / `arguments` / `payload` | what was sent and returned |

`format` is `mailgent-mcp-tester-session/v1`. Chronological `calls` (oldest first).

Scripted await-ask demos stay on `Scripts/tests/await-ask/fake_agent.py`.
