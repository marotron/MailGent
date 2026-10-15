# 02 · CLI wire format + auth

Type: decision  
Status: resolved  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/31

## Question

How should `mailgent-cli` identify agents securely, and what invoke shape avoids maintaining a second tool surface when MCP adds tools?

## Answer (locked 2026-10-13)

### Transport
- **UDS only** (`~/Library/Application Support/MailGent/cli.sock`). No TCP for CLI.
- Settings **Enable local CLI** (default off) gates the server.

### Identity
- `--agent "Name"` is routing / mismatch check only — **not** identity.
- Every call proves the **same per-agent credential** as MCP Bearer.
- Authenticate → `agentID`; reject if name does not match that agent.
- Secrets live in **Keychain**; CLI reads via env (`MAILGENT_TOKEN`) or Keychain lookup (not argv).

### Payload
- One path: MCP `tools/call` params JSON:

```bash
export MAILGENT_TOKEN=…
mailgent-cli --agent "Grok Bot" '{"name":"search","arguments":{"query":"invoice"}}'
echo '{"name":"status","arguments":{}}' | mailgent-cli --agent "Grok Bot"
```

- Thin client forwards to the same tools/call dispatcher as loopback MCP.
- **No** per-tool subcommands/flags in 0.12.0.
- **No** thin sugar (`call search --json …`).
- **No** `--json` / `--mcp` flags. Future non-tool work → new **subcommand**, not a format flag.

## Out of scope
- UI layout for Control Center (issue 01)
- Exact socket refuse matrix / packaging (plan leftovers)

## Comments

### 2026-10-13

Locked from design thread: UDS + Keychain + MCP-shaped JSON; skip sugar/format flags until a second CLI job exists. Plan `local_mailgent-cli` + proto examples updated.
