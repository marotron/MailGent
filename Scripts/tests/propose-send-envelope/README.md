# propose_send envelope guards — scripted transport

Synthetic fixtures only. No personal mail.

Companion to `PendingProposalRegistry` / `LoopbackMCPServer` unit tests for
envelope dedupe, `already_sent`, and cross-agent `conflict`.

## Self-check

```bash
python3 Scripts/tests/propose-send-envelope/fake_mailgent.py --self-check
```

| Case | Expect |
|---|---|
| Same envelope, different body | Same `proposalId`; open draft body unchanged |
| Other bearer, same envelope | `{ status: conflict, agentName, proposalId }` |
| After `send` | `{ status: already_sent }` |
| After `cancel` | New `propose_send` allowed |
| Soft `await_propose_send` | Returns `awaiting_user` under client budget |

Report: `/tmp/propose-send-envelope-fake-mailgent.json`.

## Optional live fake

```bash
python3 Scripts/tests/propose-send-envelope/fake_mailgent.py --port 8799
```

MCP URL `http://127.0.0.1:8799/mcp`. Bearer `test` → Cursor; `other` → Admin.
Scripted Send fires after `--send-delay` (default 2s) when awaiting.

## Manual dogfood (GUI)

```bash
cd Scripts/mcp-tester && npm install && npm run tauri dev
```

Point URL at live MailGent (`8788`) or this fake (`8799`). Use shortcuts
**Propose send** / **Await propose (last proposalId)** for envelope dogfood.

See [`Scripts/mcp-tester/README.md`](../../mcp-tester/README.md).

## Do not

- Treat self-check green as proof a live Grok Bot will keep one `proposalId`.
- Point the self-check / fake fixtures at real Apple Mail / personal messages.
