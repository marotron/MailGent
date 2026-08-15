# Research: Agent Interface Protocols (MCP and Alternatives)

**Question:** Using primary specifications and official documentation, how well do MCP and credible alternatives support MailGent's required local-first agent identity, scoped read/search, draft creation, approval-gated mutations, auditability, revocation, and explicit user-mediated remote sessions?

**Access date for all citations unless noted:** 2026-08-15  
**Spec baseline (MCP):** [Model Context Protocol specification 2025-11-25](https://modelcontextprotocol.io/specification/2025-11-25)  
**Out of scope:** Blog posts, secondary roundups, vendor marketing without first-party normative docs

---

## 1. Decision-oriented summary

| MailGent requirement | MCP (2025-11-25) | A2A (Linux Foundation / Google-origin) | OpenAI / Anthropic tool use | Apple App Intents | Raw JSON-RPC 2.0 |
| --- | --- | --- | --- | --- | --- |
| Local-first agent identity | **Partial.** HTTP path can identify OAuth clients + tokens; stdio path intentionally avoids OAuth and uses env credentials. No first-class “agent registry” with local-vs-remote trust tiers. | **Partial.** Auth identity at HTTP/TLS layer via Agent Card `securitySchemes`; authorization model is agent-defined, not prescribed. Oriented to remote agent↔agent, not on-device mailbox gatekeeping. | **Poor fit as agent bus.** Tools execute in *your* app after the model returns a call; no multi-agent local identity protocol. | **Different surface.** Intents are for Apple Intelligence / Siri / Shortcuts discovery, not third-party agent grants. | **None.** Message format only. |
| Scoped read / search | **Partial.** OAuth scopes + resource/tool access controls are recommended; tool/resource schemas can express read ops. Fine-grained mailbox selectors (account, folder, sender, date) are **application-defined**, not protocol-native. | **Partial.** Skill-based / OAuth scope authorization is recommended but defined by the agent. Task messaging is not a mail search API. | **App-owned.** You choose which tools the model may see; no mailbox grant model. | **System-mediated parameters**, not MailGent-style agent grants. | App-defined methods. |
| Draft creation | **Good as tool surface.** `tools/call` can expose `create_draft`; annotations can hint non-destructive. Enforcement is server-side. | Possible as a skill/task; not specialized for mail. | Possible as a client-executed function. | Possible as an App Intent action. | Possible as custom method. |
| Approval-gated mutations | **Guidance, not enforcement.** Spec says hosts **SHOULD** keep a human in the loop and consent before tool invocation; MCP “cannot enforce these security principles at the protocol level.” Elicitation / sampling add more HITL hooks. | **Partial.** `TASK_STATE_AUTH_REQUIRED` signals need for authorization / human approval; scope/revocation of that decision is **not** defined by A2A. | **App-owned.** You can refuse to execute `tool_use` / function calls until UI approval. | **Strong HITL primitives** (`requestConfirmation`, auth policies) for *system* invocation paths. | App-owned. |
| Auditability | **Weak native.** Logging utility is server→client syslog-style notifications, not an append-only access ledger. Clients **SHOULD** log tool usage. | **Guidance.** Enterprise docs recommend comprehensive logging/auditing; protocol does not define an audit log schema. | App logs. | System may donate intents; not a MailGent agent access log. | App logs. |
| Revocation | **Partial (HTTP/OAuth).** Token invalidation / session DELETE / 401–403; OAuth AS details “beyond the scope” of MCP. No stdio grant-revocation model. Scope minimization notes revocation friction for broad tokens. | **Partial.** Credentials/tokens out-of-band; in-task auth “does not define… revocation semantics.” | Token/API key lifecycle outside tool protocol. | User disables Shortcuts / intent discovery — not agent grant revocation. | App-owned. |
| User-mediated remote sessions (no unattended inbound) | **Tension.** Streamable HTTP is designed for independently reachable servers; Anthropic’s MCP connector requires a **publicly exposed** HTTP MCP server and **cannot** use local STDIO. Fits only if MailGent opens a **time-bounded, user-started** tunnel/session and never leaves a standing inbound endpoint. | **Mismatch.** A2A assumes production HTTPS agent endpoints and enterprise web patterns; push webhooks amplify always-on exposure risk. | Remote by nature (cloud model API). | Local/system; not remote agent sessions. | Transport-agnostic; policy is yours. |
| **Overall fit for MailGent v1** | **Best interoperability substrate** for external AI hosts that already speak MCP — **if** MailGent owns policy, approval, audit, and session lifecycle as the MCP **server / resource server**. | Better for agent↔agent task collaboration later; wrong primary layer for mailbox tool access. | Complementary *inside* an agent host; not a substitute for MailGent’s agent gate. | Valuable for Apple-native UX alongside MailGent; not the external-agent interface. | Fall back / custom transport only. |

**Verdict:** Prefer **MCP as the external-agent wire protocol** (MailGent = MCP server exposing scoped tools/resources). MailGent must **own** identity registry, grant store, fine-grained mailbox scopes, approval queue, append-only audit log, local-vs-remote privilege tiers, and remote-session mediation. Do not treat MCP (or A2A) as providing those product controls out of the box.

---

## 2. MailGent topology vs protocol roles

MailGent product notes require: device-first policy; local agents connect directly; remote agents only via explicit user-mediated sessions; no unattended inbound endpoint; agents get identity, scopes, capabilities, revocable grants, and a comprehensive append-only access log.

MCP’s own role model:

- **Hosts:** LLM applications that initiate connections  
- **Clients:** connectors inside the host  
- **Servers:** services that provide context and capabilities  

([MCP Specification — Overview](https://modelcontextprotocol.io/specification/2025-11-25))

Implication for MailGent: the natural mapping is **MailGent as MCP server** (mailbox authority) and **external agent hosts as MCP clients**. That inverts the common “Claude Desktop launches a local filesystem MCP subprocess” demo for a long-running macOS companion: MailGent is not typically launched *by* the agent via stdio; it is already running and must **accept** connections under MailGent-controlled policy.

---

## 3. Model Context Protocol — confirmed facts

### 3.1 Base protocol

- MCP uses **JSON-RPC 2.0** messages between hosts/clients and servers; stateful connections; capability negotiation. ([MCP Specification](https://modelcontextprotocol.io/specification/2025-11-25); [JSON-RPC 2.0](https://www.jsonrpc.org/specification))
- Servers may expose **Resources**, **Prompts**, and **Tools**. Clients may expose **Sampling**, **Roots**, and **Elicitation**. Utilities include progress, cancellation, errors, and logging. ([MCP Specification](https://modelcontextprotocol.io/specification/2025-11-25))

### 3.2 Transports: stdio, Streamable HTTP, legacy SSE

Current standard transports ([Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)):

1. **stdio** — Client launches the MCP server as a **subprocess**; JSON-RPC over stdin/stdout (newline-delimited); stderr for optional logs. Clients **SHOULD** support stdio whenever possible.
2. **Streamable HTTP** — Server is an **independent process** that can handle multiple clients; single MCP endpoint with POST (and optional GET for SSE). Optional SSE streaming; session via `MCP-Session-Id`; client **SHOULD** DELETE session when done. Replaces older **HTTP+SSE** (protocol 2024-11-05); backwards-compat guidance is documented.

Security requirements for Streamable HTTP:

- **MUST** validate `Origin` (DNS rebinding); invalid Origin → HTTP 403  
- Local servers **SHOULD** bind only to localhost (127.0.0.1), not `0.0.0.0`  
- Servers **SHOULD** implement proper authentication for all connections  

Custom transports **MAY** be implemented if they preserve JSON-RPC and lifecycle requirements (e.g., unix domain sockets). ([Transports](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports); [Security Best Practices — Local MCP Server Compromise](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices))

**MailGent note:** A persistent macOS app fits **localhost Streamable HTTP**, **custom IPC**, or a **user-launched bridge** better than classic “client spawns MailGent via stdio.” Stdio still useful for a thin local bridge process that MailGent manages.

### 3.3 Authorization / identity

Authorization is **OPTIONAL**. When used ([Authorization](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)):

- Applies to **HTTP-based** transports; based on **OAuth 2.1** subset + Protected Resource Metadata (RFC 9728), AS metadata (RFC 8414) / OIDC discovery, optional DCR (RFC 7591), Client ID Metadata Documents.
- MCP **server** = OAuth **resource server**; MCP **client** = OAuth **client**; AS issues tokens (AS implementation details **beyond scope** of MCP).
- **STDIO** implementations **SHOULD NOT** follow the HTTP OAuth flow; they **SHOULD** retrieve credentials from the **environment**.
- Access tokens sent as `Authorization: Bearer`; audience binding required; 401 vs 403 for auth vs insufficient scope.
- Scopes: `WWW-Authenticate` may carry `scope=`; clients have a documented **scope selection strategy**; step-up via `insufficient_scope` challenges.
- Security best practices emphasize **scope minimization** and note that broad tokens raise **revocation friction** and audit noise. ([Scope Minimization](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices))

**What MCP does *not* define:** a MailGent-style agent object with trust tier (local trusted vs remote), private scopes, append-only grant history, or product-level revoke UI. Token lifetime / revocation is left to the authorization server.

### 3.4 Tools, resources, prompts

**Tools** ([Tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)):

- Model-controlled discovery (`tools/list`) and invocation (`tools/call`) with JSON Schema inputs/optional outputs.
- **SHOULD** always have a human in the loop able to deny invocations; hosts **MUST** obtain explicit user consent before invoking tools (trust principles on overview page).
- Clients **MUST** treat tool **annotations as untrusted** unless from a trusted server.
- Annotations (hints only): `readOnlyHint`, `destructiveHint`, `idempotentHint`, `openWorldHint`. ([Schema — ToolAnnotations](https://modelcontextprotocol.io/specification/2025-11-25/schema))
- Security: servers **MUST** validate inputs, implement access controls, rate-limit; clients **SHOULD** confirm sensitive ops, show inputs, validate results, timeouts, and **log tool usage for audit**.

**Resources** ([Resources](https://modelcontextprotocol.io/specification/2025-11-25/server/resources)): URI-addressed context; list/read/subscribe; access controls **SHOULD** be implemented; URI validation **MUST**.

**Prompts:** templated workflows for users (server feature listed in overview). Useful for guided UX, not for MailGent’s agent identity model.

**Fit for mail ops:** Map `search` / `read_message` as read-only tools or resources; `create_draft` as additive write; `send` / `delete` / `move` as destructive tools that MailGent refuses until the human approval queue clears — protocol carries the call; MailGent enforces the gate.

### 3.5 Sampling and elicitation (HITL hooks)

**Sampling** ([Sampling](https://modelcontextprotocol.io/specification/2025-11-25/client/sampling)): server asks the **client** to run an LLM completion; **SHOULD** keep human-in-the-loop for deny/edit of prompts and results; optional tools-in-sampling with further approval steps. This is **server→client LLM access**, not MailGent approving mailbox mutations.

**Elicitation** ([Elicitation](https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation)): server requests user info via client — **form** mode (structured, not for secrets) or **URL** mode (out-of-band for credentials). Useful for consent / OAuth-style step-up UX; not a substitute for MailGent’s mutation approval queue.

### 3.6 Logging vs audit ledger

MCP **logging** ([Logging](https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/logging)) is optional `logging` capability: servers emit `notifications/message` with syslog levels; clients **MAY** persist. It is **not** an append-only, agent-attributed access log of every mail read/search/draft/approve. Spec security for logs forbids credentials/PII in log payloads — conflicting with a mail audit trail that must record *which* message was accessed (product must separate operational MCP logs from MailGent’s privacy-preserving access ledger).

### 3.7 Security and trust principles (normative intent)

MCP overview states ([Specification — Security and Trust & Safety](https://modelcontextprotocol.io/specification/2025-11-25)):

1. User consent and control  
2. Data privacy (hosts must get consent before exposing user data to servers)  
3. Tool safety (consent before any tool; treat annotations carefully)  
4. LLM sampling controls  

And explicitly: **“While MCP itself cannot enforce these security principles at the protocol level, implementors SHOULD…”** build consent flows, access controls, etc.

Local compromise mitigations: prefer stdio to limit who can talk to the server; if HTTP, require auth tokens or restricted IPC (unix sockets). ([Security Best Practices](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices))

Session hijacking guidance: sessions are **not** authentication; use secure session IDs; bind sessions to user identity. ([Security Best Practices](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices))

### 3.8 Ecosystem remote MCP — Anthropic connector constraint

Anthropic’s official **MCP connector** (Messages API beta) connects to **remote** MCP servers over HTTP (Streamable HTTP or SSE), supports OAuth Bearer tokens and tool allow/deny lists, and states: **“Local STDIO servers cannot be connected directly”** and the server **must be publicly exposed through HTTP**. Only tool calls are supported from the MCP feature set. ([MCP connector](https://platform.claude.com/docs/en/agents-and-tools/mcp-connector))

**Product implication:** Cloud-hosted agent products that expect a public MCP URL conflict with MailGent’s “no unattended inbound endpoint” unless the user **explicitly starts** a mediated remote session (ephemeral tunnel + short-lived token) and MailGent shuts it down when the session ends.

---

## 4. Credible alternatives — primary sources

### 4.1 Agent2Agent (A2A) Protocol

- Official spec: [A2A Protocol Specification](https://a2a-protocol.org/latest/specification/) (v1.0.0 documented).  
- Project home: [github.com/a2aproject/A2A](https://github.com/a2aproject/A2A).  
- Linux Foundation announced the A2A project (Google-origin protocol) on 2025-06-23. ([LF press release](https://www.linuxfoundation.org/press/linux-foundation-launches-the-agent2agent-protocol-project-to-enable-secure-intelligent-communication-between-ai-agents))

**What it is:** Interop between **opaque agents** — discover capabilities (Agent Card), negotiate modalities, manage collaborative **Tasks**, exchange messages/artifacts — **without** sharing internal tools/memory. Bindings: JSON-RPC, gRPC, HTTP/REST. ([A2A Spec §1](https://a2a-protocol.org/latest/specification/))

**AuthZ:** Treat agents as enterprise HTTP apps; identity in headers (OAuth2/OIDC/API keys), not in JSON-RPC payload; authorization **implementation-specific** (skills, actions, data policies, OAuth scopes). In-task authorization via `TASK_STATE_AUTH_REQUIRED`; protocol **does not** define scope, validity, or **revocation** of that authorization. ([A2A Spec §7](https://a2a-protocol.org/latest/specification/); [Enterprise-Ready](https://a2a-protocol.org/latest/topics/enterprise-ready/))

**Security posture:** Production **MUST** use HTTPS/TLS; recommend auditing significant events; authorization boundaries are agent-defined. Push notification webhooks require careful SSRF controls. ([A2A Spec §13](https://a2a-protocol.org/latest/specification/); [Enterprise-Ready](https://a2a-protocol.org/latest/topics/enterprise-ready/))

**Fit:** Strong for multi-agent task orchestration; weak as MailGent’s **mailbox capability API**. Could later wrap MailGent as an “email agent,” but MCP tools/resources map more directly to read/search/draft/approve.

### 4.2 OpenAI function / tool calling

OpenAI documents **function calling / tool calling** as a multi-step loop: app sends tool schemas → model returns tool calls → **application executes** → app returns outputs → model continues. Built-in platform tools include web search, code execution, **MCP server access**, etc. ([Function calling](https://platform.openai.com/docs/guides/function-calling); [Tools](https://platform.openai.com/docs/guides/tools))

**Fit:** This is how an OpenAI-based **host** would call MailGent **after** connecting (often via MCP or custom functions). It does not provide local agent identity, grants, audit, or user-mediated remote sessions for MailGent itself.

### 4.3 Anthropic tool use

Anthropic documents **client tools** (your app executes `tool_use` and returns `tool_result`) vs **server tools** (Anthropic executes). For MCP servers, see MCP connector / build-client guidance. ([Tool use overview](https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview))

**Fit:** Same as OpenAI — model↔host tool loop. Approval gating and audit live in the host or in MailGent as the tool backend. Remote MCP connector’s public-HTTP requirement is a first-party constraint for cloud Claude API use ([MCP connector](https://platform.claude.com/docs/en/agents-and-tools/mcp-connector)).

### 4.4 Apple App Intents / Apple Intelligence surface

Apple’s **App Intents** framework makes actions/data discoverable by **Apple Intelligence**, Siri, Shortcuts, Spotlight, widgets, etc. ([App Intents](https://developer.apple.com/documentation/appintents); [AppIntent](https://developer.apple.com/documentation/appintents/appintent))

Relevant first-party controls:

- `authenticationPolicy` / `IntentAuthenticationPolicy` (alwaysAllowed, requiresAuthentication, requiresLocalDeviceAuthentication). ([IntentAuthenticationPolicy](https://developer.apple.com/documentation/appintents/intentauthenticationpolicy))  
- `requestConfirmation` and related confirmation APIs on `AppIntent`. ([AppIntent](https://developer.apple.com/documentation/appintents/appintent))

**Fit:** Excellent for **human / system** invocation of MailGent actions on macOS; **not** a protocol for arbitrary third-party AI agents to obtain revocable, audited mailbox grants. Complementary product surface, not MCP substitute.

### 4.5 JSON-RPC 2.0 (custom local servers)

[JSON-RPC 2.0](https://www.jsonrpc.org/specification) is transport-agnostic request/response/notification framing. MCP and A2A reuse it. Alone it provides **no** auth, scopes, audit, or HITL.

**Fit:** Acceptable as a private MailGent↔bridge framing if MCP overhead is unwanted — but you forfeit ecosystem clients (Claude Desktop, Cursor, Anthropic MCP connector, etc.) unless you also speak MCP.

---

## 5. Requirement-by-requirement analysis

### 5.1 Local-first agent identity

| Layer | Status |
| --- | --- |
| MCP OAuth client_id / tokens (HTTP) | Usable building block for “who is calling” |
| MCP stdio | Env credentials; no OAuth client registry |
| MailGent agent registry, trust tier, display name, install attestation | **Must own** |

### 5.2 Scoped read / search

MCP can expose narrow tools and challenge for additional OAuth scopes; resources can be URI-gated. MailGent’s selectors (account, folder, sender/domain, date, headers/body/attachments, smart folders) are **policy engine** work: filter every `tools/call` / `resources/read` against the grant before returning data.

### 5.3 Draft creation

Expose as tool with `readOnlyHint: false`, `destructiveHint: false` (additive). Still enforce grant + audit on the server.

### 5.4 Approval-gated mutations

Do **not** rely on clients honoring SHOULD-level HITL. Pattern:

1. Mutation tools either (a) create an **approval request** resource and return pending status, or (b) block until elicitation/URL consent completes.  
2. Human resolves in MailGent UI (product requirement).  
3. Only then perform send/delete/move.

A2A’s `TASK_STATE_AUTH_REQUIRED` is analogous but for agent tasks, not mail mutations.

### 5.5 Auditability

Implement MailGent append-only access log **outside** MCP logging utility. Optionally emit redacted MCP log notifications for host UIs. Record: agent id, grant id, operation, resource identifiers, decision (allow/deny/pending), timestamps.

### 5.6 Revocation

HTTP: invalidate tokens, delete sessions (`MCP-Session-Id` DELETE), refuse with 401/403. Product: revoke grant → immediately deny tools even if a host still holds a cached tool list (use `listChanged` / empty tool set after revoke). Stdio bridges: kill process + wipe env tokens.

### 5.7 Explicit user-mediated remote sessions

Protocol-compatible patterns that preserve “no unattended inbound”:

- Default: **localhost-only** Streamable HTTP or UDS; no WAN bind.  
- Remote: user starts session → MailGent (or OS) opens **ephemeral** reachability (e.g., short-lived reverse tunnel) + short-lived OAuth token with remote-denied private scopes → user ends session → tear down listener and revoke token.  
- Reject standing public MCP URLs required by cloud connectors unless the user knowingly enables a mediated session that satisfies that constraint.

---

## 6. Gaps MailGent must fill itself

Regardless of MCP adoption, primary specs leave these to the implementor:

1. **Agent identity model** — local trusted vs remote; registration; attestation of local processes.  
2. **Grant store** — capabilities, mailbox selectors, expiry, revoke, private scopes.  
3. **Policy enforcement** — every read/search/draft/mutation checked server-side.  
4. **Approval queue** — human UI for send/delete/move (and any other mutation).  
5. **Append-only access log** — comprehensive, agent-attributed, retention, export.  
6. **Session mediator** — start/stop remote access without unattended inbound.  
7. **Tool catalog design** — map mail operations to MCP tools/resources with least privilege.  
8. **Authorization server** — if using MCP OAuth: issue/rotate/revoke tokens, consent UX, scope taxonomy.  
9. **Defense in depth** — Origin checks, localhost bind, UDS permissions, rate limits (aligned with MCP security docs but product-owned).

---

## 7. Implications for product definition

1. **Spec language:** “External agents connect via MCP (or a documented MCP-compatible bridge). MailGent is the MCP server and sole policy enforcement point.”  
2. **Do not claim** MCP provides audit or approval; claim MailGent provides them **on top of** MCP.  
3. **Local agents:** prefer localhost HTTP with per-agent tokens, or supervised stdio bridge — not “any process on the machine.”  
4. **Remote agents:** productize **session** as a first-class object; document incompatibility with always-on public MCP URLs except during an active session.  
5. **App Intents:** parallel track for Siri/Shortcuts/Apple Intelligence — not the agent-safety differentiator.  
6. **A2A:** park for multi-agent orchestration; not required for v1 mailbox access.  
7. **OpenAI/Anthropic tool use:** hosts will use these *internally*; MailGent still presents MCP (or functions that call MailGent).

---

## 8. Open risks

| Risk | Why it matters | Mitigation direction |
| --- | --- | --- |
| Role inversion vs stdio demos | Agents expect to spawn servers; MailGent is long-lived | Document connection model; ship a thin MCP bridge |
| Cloud MCP connectors need public HTTP | Conflicts with no unattended inbound | User-mediated ephemeral sessions only; refuse standing exposure |
| HITL is SHOULD, not MUST | Malicious or careless hosts may auto-invoke tools | Enforce approvals **inside MailGent** before side effects |
| Annotation / scope trust | Annotations are hints; broad OAuth scopes are dangerous | Ignore untrusted annotations for authZ; minimize scopes; server-side checks |
| Confused deputy / proxy patterns | Documented MCP OAuth proxy attacks | Avoid proxying third-party mail OAuth through shared static clients without per-client consent ([Security Best Practices](https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices)) |
| Audit vs MCP log PII rules | MCP logging forbids PII; mail audit needs message refs | Separate ledgers; careful redaction in any MCP-facing logs |
| A2A webhook/SSRF surface | Enterprise A2A push patterns assume reachable endpoints | Keep A2A out of v1 device-first path |
| Ecosystem fragmentation | Hosts differ (full MCP vs tools-only connector) | Design tools-first; treat resources/prompts as optional |

---

## 9. Sources (primary)

| Topic | URL |
| --- | --- |
| MCP spec index (2025-11-25) | https://modelcontextprotocol.io/specification/2025-11-25 |
| MCP transports | https://modelcontextprotocol.io/specification/2025-11-25/basic/transports |
| MCP authorization | https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization |
| MCP security best practices | https://modelcontextprotocol.io/specification/2025-11-25/basic/security_best_practices |
| MCP tools | https://modelcontextprotocol.io/specification/2025-11-25/server/tools |
| MCP resources | https://modelcontextprotocol.io/specification/2025-11-25/server/resources |
| MCP sampling | https://modelcontextprotocol.io/specification/2025-11-25/client/sampling |
| MCP elicitation | https://modelcontextprotocol.io/specification/2025-11-25/client/elicitation |
| MCP logging | https://modelcontextprotocol.io/specification/2025-11-25/server/utilities/logging |
| MCP schema / ToolAnnotations | https://modelcontextprotocol.io/specification/2025-11-25/schema |
| JSON-RPC 2.0 | https://www.jsonrpc.org/specification |
| A2A specification | https://a2a-protocol.org/latest/specification/ |
| A2A enterprise-ready | https://a2a-protocol.org/latest/topics/enterprise-ready/ |
| A2A GitHub | https://github.com/a2aproject/A2A |
| Linux Foundation A2A announcement | https://www.linuxfoundation.org/press/linux-foundation-launches-the-agent2agent-protocol-project-to-enable-secure-intelligent-communication-between-ai-agents |
| OpenAI function calling | https://platform.openai.com/docs/guides/function-calling |
| OpenAI tools overview | https://platform.openai.com/docs/guides/tools |
| Anthropic tool use | https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview |
| Anthropic MCP connector | https://platform.claude.com/docs/en/agents-and-tools/mcp-connector |
| Apple App Intents | https://developer.apple.com/documentation/appintents |
| Apple AppIntent | https://developer.apple.com/documentation/appintents/appintent |
| Apple IntentAuthenticationPolicy | https://developer.apple.com/documentation/appintents/intentauthenticationpolicy |
| OAuth 2.1 draft (referenced by MCP) | https://datatracker.ietf.org/doc/html/draft-ietf-oauth-v2-1-13 |
| RFC 9728 Protected Resource Metadata | https://datatracker.ietf.org/doc/html/rfc9728 |
