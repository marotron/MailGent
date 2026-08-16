# Lock MailGent v1 Product

Label: wayfinder:map

## Destination

Produce a locked, implementation-ready v1 product specification for MailGent: a macOS-first agent-safe email companion for individuals who continue using Apple Mail, differentiated by controlled access for external AI agents. Stop before technical architecture, technology selection, delivery planning, or implementation tickets.

## Notes

- Initial user: technical or power user already using external AI agents and managing multiple personal/work inboxes.
- Platform: macOS first. iPhone and iPad follow after the core companion proves useful.
- v1 providers: Gmail and Yahoo. Microsoft 365/Exchange and Proton belong to a later version.
- Product role: agent-safe companion alongside Apple Mail, not a replacement daily client.
- Human surfaces: account connection; unified and per-account scoped search/read; draft inspection/editing; mutation approvals; policy and audit management; opening source messages in Apple Mail; soft delete (Trash) and hard delete (permanent) for Gmail and Yahoo.
- External-agent access is the differentiator; no built-in assistant in v1.
- Device-first: mailbox cache, search index, credentials, and policy enforcement stay on-device. MailGent cloud does not read mailbox content.
- Local agents can connect directly. Remote agents require explicit user-mediated sessions. No unattended inbound endpoint.
- Every agent has its own identity, scopes, capabilities, revocable grants, and comprehensive append-only access log. Trusted local agents may receive private scopes denied to remote agents.
- Agent reads/searches are restricted to explicit grants. Agents may create drafts. Send, soft delete (move/label to Trash), hard delete (permanent purge), move, and other mutations require human approval.
- Soft delete and hard delete are both agent-proposeable when the agent has the matching capability; both still require one-shot human approval. Soft delete → Trash (recoverable). Hard delete → permanent purge (extra confirmation in the approval UI). Humans may also soft/hard delete directly in the companion UI.
- v1 policy selectors: account, folder/mailbox, sender/recipient address or domain, date range, headers/body/attachments, and reusable allow/deny smart folders.
- Approval starts as a simple in-app action queue. Optional macOS notifications are configurable by event severity and remain local.
- Use `/prototype` for prototype tickets and `/research` for research tickets.

## Decisions so far

- [Research Gmail and Yahoo Integration Constraints](issues/02-research-gmail-yahoo-integration.md) — Gmail API + OAuth preferred; Yahoo is IMAP/SMTP OAuth after commercial approval; Gmail push needs Pub/Sub backend; keep mailbox content on-device
- [Define v1 Success and Product Acceptance Boundary](issues/01-define-v1-success.md) — v1 is a macOS agent-safe companion to Apple Mail with scoped access, approvals, revocation, comprehensive local auditing, and optional local notifications
- [Research Apple Platform Constraints](issues/03-research-apple-platform-constraints.md) — macOS sync needs consented helpers (no native BGAppRefresh); Keychain for tokens; sandboxed XPC/localhost for agents; local notifications OK; MAS sandbox vs Developer ID+notarization choice pending
- [Research External-Agent Interface Protocols](issues/04-research-agent-interface-protocols.md) — MCP best wire protocol (MailGent as server); product must own identity, grants, approvals, audit, remote sessions; A2A/App Intents/tool-calling are complementary not substitutes
- Soft vs hard delete — Agents may propose soft delete → Trash or hard/permanent delete when granted the matching capability; both are approval-gated. Soft delete is recoverable; hard delete needs stronger confirmation in the approval UI. Humans may also soft/hard delete directly in the companion. Empty Trash / purge bulk actions remain human-only if exposed.
- [Define the Canonical Mailbox Model](issues/05-define-canonical-mailbox-model.md) — Placement vs flags (Yahoo max one placement); archive = Gmail drop INBOX / Yahoo Archive folder + virtual Archived view; no cross-account threads; drafts owned by one account+From; unified search merges hits with account+placement; soft vs hard delete distinguished (agent propose detail in 08)
- [Choose Agent Runtime and Cross-Device Topology](issues/06-choose-agent-runtime-topology.md) — MailGent owns sessions; v1 supports UDS plus hardened loopback MCP; agent trust is per-device; iCloud syncs only non-sensitive UI preferences; remote access uses explicit, expiring sessions over an opaque end-to-end encrypted relay
- [Define Per-Agent Authorization and Exposure](issues/07-define-agent-authorization.md) — Deny-by-default; product-agnostic agents (not models); classes `lan-inference` / `machine-local` / `remote`; private/regular/remote-eligible scopes; deny wins; AND/OR selectors; field groups; smart folders; duration/revocation/explanation without leak; data grants separate from capabilities (incl. soft-delete and hard-delete caps)
- [Define Agent Operations and Redaction Contract](issues/08-define-agent-operation-contract.md) — Read ops capability-only; drafts capability-only; send/trash/hard-delete/move/label/archive/flags need approval; search deny-filtered with cursor pages; omit without redaction stubs; no v1 persistent auto-approve
- [Define Companion Human-Surface Behaviors](issues/12-define-human-mail-baseline.md) — Companion control plane (not daily client): OAuth accounts + sync health; unified/per-account search-read; open in Apple Mail; draft inspect/edit; approval queue (incl. soft + hard delete proposals); policy/audit; direct soft + hard delete with confirm
- [Define Security, Audit, and Recovery Behavior](issues/13-define-security-audit-recovery.md) — Keychain-only credentials; lock pauses sessions; fail closed; stale reads only; append-only local audit with Touch ID manual purge; local severity notifications; confirmed destructive recovery
- [Decide Gmail Push Posture Under Device-First](issues/14-decide-gmail-push-posture.md) — v1 polling/history-sync only (no Pub/Sub relay); Yahoo IDLE/poll on local helper; content-blind push deferred
- [Prototype Companion Search and Review Navigation](issues/09-prototype-mailbox-navigation.md) — Default home = control-first; settings may switch to search-first or review desk; account+placement always visible
- [Prototype Agent Access Policy Authoring](issues/10-prototype-policy-authoring.md) — Ship wizard A + grant desk B; scope-then-access selectors; resource caps (not free-form Write); explicit Deny carve-outs; pairing finish-setup deferred to 17
- [Prototype Agent Mutation Approval](issues/11-prototype-mutation-approval.md) — Ship queue A + focus B + batch C; approve/deny/edit-then-approve; soft + hard delete with stronger hard-delete confirm; no auto-approve; expiry cancels pending

## Not yet specified

- MAS sandbox vs Developer ID + notarization, and how early distribution works under Gmail/Yahoo approval caps, still open ([16](issues/16-decide-early-distribution.md); unblocked after Yahoo access task).
- Agent pairing finish-setup UX after identity + trust class (pairing challenge, credential, local/MCP path, host config help, status, remote session open) — tracked in [17](issues/17-prototype-agent-pairing-setup.md).

## Out of scope

- Microsoft 365/Exchange and Proton provider support: planned for v2, not this v1 specification.
- Built-in AI assistant or model hosting.
- Regex, wildcard, or AI-classified access rules.
- Unattended remote-agent access.
- Replacement-mail-client behavior, iPhone/iPad delivery, inbox notifications, manual filing, daily-client parity, calendar, contacts management, advanced visual customization, and server-side rule editing. (Companion soft/hard delete for Gmail and Yahoo remains in scope; agents may propose either with approval.)
- Technical architecture, framework selection, storage implementation, build plan, and implementation tickets.
