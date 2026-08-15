# Lock MailGent v1 Product

Label: wayfinder:map

## Destination

Produce a locked, implementation-ready v1 product specification for MailGent: a macOS-first agent-safe email companion for individuals who continue using Apple Mail, differentiated by controlled access for external AI agents. Stop before technical architecture, technology selection, delivery planning, or implementation tickets.

## Notes

- Initial user: technical or power user already using external AI agents and managing multiple personal/work inboxes.
- Platform: macOS first. iPhone and iPad follow after the core companion proves useful.
- v1 providers: Gmail and Yahoo. Microsoft 365/Exchange and Proton belong to a later version.
- Product role: agent-safe companion alongside Apple Mail, not a replacement daily client.
- Human surfaces: account connection; unified and per-account scoped search/read; draft inspection/editing; mutation approvals; policy and audit management; opening source messages in Apple Mail.
- External-agent access is the differentiator; no built-in assistant in v1.
- Device-first: mailbox cache, search index, credentials, and policy enforcement stay on-device. MailGent cloud does not read mailbox content.
- Local agents can connect directly. Remote agents require explicit user-mediated sessions. No unattended inbound endpoint.
- Every agent has its own identity, scopes, capabilities, revocable grants, and comprehensive append-only access log. Trusted local agents may receive private scopes denied to remote agents.
- Agent reads/searches are restricted to explicit grants. Agents may create drafts. Send, delete, move, and other mutations require human approval.
- v1 policy selectors: account, folder/mailbox, sender/recipient address or domain, date range, headers/body/attachments, and reusable allow/deny smart folders.
- Approval starts as a simple in-app action queue. Optional macOS notifications are configurable by event severity and remain local.
- Use `/prototype` for prototype tickets and `/research` for research tickets.

## Decisions so far

- [Research Gmail and Yahoo Integration Constraints](issues/02-research-gmail-yahoo-integration.md) — Gmail API + OAuth preferred; Yahoo is IMAP/SMTP OAuth after commercial approval; Gmail push needs Pub/Sub backend; keep mailbox content on-device
- [Define v1 Success and Product Acceptance Boundary](issues/01-define-v1-success.md) — v1 is a macOS agent-safe companion to Apple Mail with scoped access, approvals, revocation, comprehensive local auditing, and optional local notifications

## Not yet specified

- Whether any low-risk mutation can later receive persistent automation approval depends on the operation and approval models.
- App Store distribution, extensions, and entitlement implications depend on Apple-platform feasibility findings.
- Attachment-specific disclosure and handling may need finer policy after the agent operation contract is known.
- Failure, recovery, and degraded/offline behavior cannot be finalized until Apple platform constraints and agent topology are known.

## Out of scope

- Microsoft 365/Exchange and Proton provider support: planned for v2, not this v1 specification.
- Built-in AI assistant or model hosting.
- Regex, wildcard, or AI-classified access rules.
- Unattended remote-agent access.
- Replacement-mail-client behavior, iPhone/iPad delivery, inbox notifications, manual filing, daily-client parity, calendar, contacts management, advanced visual customization, and server-side rule editing.
- Technical architecture, framework selection, storage implementation, build plan, and implementation tickets.
