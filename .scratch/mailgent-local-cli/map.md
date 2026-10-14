# Local CLI + custom agent endpoints

Label: wayfinder:map

## Destination

Ship Settings-gated `mailgent-cli` plus **user-defined agent endpoints** (any number): name, optional icon, MCP and/or CLI. Replaces fixed Cursor/Grok Control Center cards. Stop when `feat/local-cli` merges (target **0.12.0**). See plan `local_mailgent-cli`.

## Notes

- Agents are endpoints, not hard-coded presets. At least one of MCP / CLI per agent.
- Grok Bot MCP HTTP connection flapped 2026-10-14/15 — **resolved**: stale token + missing mailbox grants · [#34](https://github.com/marotron/MailGent/issues/34) · [local mirror](issues/04-grok-mcp-http-intermittent.md).
- MCP path stays loopback Bearer; CLI path is **UDS** + `--agent "Name"` + **same per-agent credential**.
- CLI payload = MCP `tools/call` params JSON (`{name, arguments}`) via argv or stdin — **no** duplicated tool flags.
- Global Settings: **Enable local CLI** (default off) gates the socket server.
- Agent secrets → **Keychain** (not plaintext source of truth in `pairing.json`).
- Icon (KISS): Cursor/Grok marks, curated SF Symbols, monogram + color — no image upload in 0.12.0.

## Decisions so far

- [#32 · Proposal: Agent API settings UI](https://github.com/marotron/MailGent/issues/32) · [local mirror](issues/01-prototype-agent-api-settings.md) — Control Center layout for N agents (A/B/C); **verdict pending**
- [#31 · CLI wire format + auth](https://github.com/marotron/MailGent/issues/31) · [local mirror](issues/02-cli-wire-format.md) — **locked** (UDS, Keychain credential, MCP-shaped JSON, no dual tool surface)
- [#33 · Credential handoff](https://github.com/marotron/MailGent/issues/33) · [local mirror](issues/03-credential-handoff.md) — **locked** (Keychain = MailGent vault; callers possess Bearer / `MAILGENT_TOKEN`; no CLI Keychain-by-name; secret-free instructions; clipboard expiry)

## Not yet specified

- Persist shape in `pairing.json` (after UI lock + Keychain migration)
- Access Log / menu bar transport badge (mcp|cli)
- Exact UDS refuse rules + `mailgent-cli` packaging (CLI still requires `MAILGENT_TOKEN`; Keychain stays app-owned)

## Future ideas

- [#35 · Feature: Copy grant settings between connected agents](https://github.com/marotron/MailGent/issues/35) · [local mirror](issues/05-copy-grants-between-agents.md)
- [#36 · Feature: Export / import grant settings](https://github.com/marotron/MailGent/issues/36) · [local mirror](issues/06-export-import-grant-settings.md)
