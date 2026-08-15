# Research External-Agent Interface Protocols

Type: research
Status: resolved

## Question

Using primary specifications and official documentation, how well do MCP and credible alternatives support MailGent's required local-first agent identity, scoped read/search, draft creation, approval-gated mutations, auditability, revocation, and explicit user-mediated remote sessions?

## Answer

**MCP is the best interoperability substrate** for external AI hosts, with MailGent as the MCP **server** (tools/resources for read/search/draft; HTTP OAuth or localhost/IPC auth). MCP does **not** natively provide agent trust tiers, fine-grained mailbox grants, enforced approval gates, append-only access logs, or safe remote reachability — MailGent must own those layers. HITL and audit are SHOULD/guidance in the spec, not protocol enforcement.

**Alternatives:** A2A (LF/Google) fits agent↔agent tasks and in-task `AUTH_REQUIRED`, not mailbox tool access. OpenAI/Anthropic tool use is the host-side loop, not a local agent gate. Apple App Intents serve Siri/Shortcuts/Apple Intelligence, not third-party agent grants. Raw JSON-RPC is framing only.

**Remote tension:** Anthropic’s MCP connector requires a publicly exposed HTTP MCP server (no local STDIO) — conflicts with “no unattended inbound” unless sessions are explicit, ephemeral, and user-mediated.

Full findings: [research/agent-interface-protocols.md](../research/agent-interface-protocols.md)
