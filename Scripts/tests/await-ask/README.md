# await_ask — scripted transport (matrix E)

Synthetic fixtures only. No personal mail.

Companion to `PendingAskRegistry` / `AgentReadAPI` / `LoopbackMCPServer` unit tests.
Models the Grok-class failure: client socket budget ~30s; soft `await_ask` default **25**.

## Self-check

```bash
python3 Scripts/tests/await-ask/fake_mailgent.py --self-check
```

Covers:

| Case | Expect |
|---|---|
| Soft poll `timeout=25` under ~30s client | Returns `awaiting_user` before socket kill |
| Allow after soft | Terminal `allow` → re-`get` body |
| Dropped / aborted await | Ask stays pending; later await works |
| Dedupe | Two identical `get` opens → same `askId` |
| `superseded` | Re-`get` opens a new Ask |
| Unknown `askId` | Structured error |

Report: `/tmp/await-ask-fake-mailgent.json`.

## Optional live fake

```bash
python3 Scripts/tests/await-ask/fake_mailgent.py --port 8798
```

MCP URL `http://127.0.0.1:8798/mcp`, any bearer. Soft timeout guidance: pass `timeout` below the client socket budget (default 25 under Grok ~30). Scripted Allow fires after `--allow-delay` (default 2s).

## Manual dogfood (GUI)

For interactive Connect → tool call → soft `await_ask` against live MailGent or the fake server, use the Tauri tester:

```bash
cd Scripts/mcp-tester && npm install && npm run tauri dev
```

See [`Scripts/mcp-tester/README.md`](../../mcp-tester/README.md). Point URL at `http://127.0.0.1:8788/mcp` (MailGent) or `http://127.0.0.1:8798/mcp` (fake below).

## Fake agent (scripted protocol)

Same contract a real agent should speak: `get` → soft `await_ask` polls → on `allow` → re-`get` body. Prefer this for automated demos; use the GUI for manual probing.

```bash
# Terminal A
python3 Scripts/tests/await-ask/fake_mailgent.py --port 8798

# Terminal B
python3 Scripts/tests/await-ask/fake_agent.py --url http://127.0.0.1:8798/mcp
```

Against a running MailGent (Ask grant + prompts on):

```bash
export MAILGENT_BEARER="…"
python3 Scripts/tests/await-ask/fake_agent.py \
  --account-id … --placement INBOX --id …
```

Report: `/tmp/await-ask-fake-agent.json`.

## Do not

- Treat self-check green as proof a live Grok Bot will call `await_ask` (matrix F).
- Point the self-check / fake fixtures at real Apple Mail / personal messages.
