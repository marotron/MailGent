# Lock MailGant v1 Product

Label: wayfinder:map

## Destination

Produce a locked, implementation-ready v1 product specification for MailGant: an Apple-ecosystem email client for individuals, differentiated by safe access for external AI agents. Stop before technical architecture, technology selection, delivery planning, or implementation tickets.

## Notes

- Initial user: technical or power user already using external AI agents and managing multiple personal/work inboxes.
- Platforms: macOS, iPhone, and iPad.
- v1 providers: Gmail and Yahoo. Microsoft 365/Exchange and Proton belong to a later version.
- Human experience: both unified and per-account views, with source account always clear.
- Human baseline: read threads; compose, reply, forward, and send; drafts; search; folders/labels; archive, move, delete, flag, mark read/unread; attachments; notifications; offline cached reading.
- External-agent access is the differentiator; no built-in assistant in v1.
- Device-first: mailbox cache, search index, credentials, and policy enforcement stay on-device. MailGant cloud does not read mailbox content.
- Local agents can connect directly. Remote agents require explicit user-mediated sessions. No unattended inbound endpoint.
- Every agent has its own identity, scopes, capabilities, revocable grants, and audit trail. Trusted local agents may receive private scopes denied to remote agents.
- Agent reads/searches are restricted to explicit grants. Agents may create drafts. Send, delete, move, and other mutations require human approval.
- v1 policy selectors: account, folder/mailbox, sender/recipient address or domain, date range, headers/body/attachments, and reusable allow/deny smart folders.
- Approval starts as a simple in-app action queue; exact delivery channels remain undecided.
- Use `/prototype` for prototype tickets and `/research` for research tickets.

## Decisions so far

- [Research Gmail and Yahoo Integration Constraints](issues/02-research-gmail-yahoo-integration.md) — Gmail API + OAuth preferred; Yahoo is IMAP/SMTP OAuth after commercial approval; Gmail push needs Pub/Sub backend; keep mailbox content on-device

## Not yet specified

- Whether approval requests need notification surfaces beyond the in-app queue depends on the approval-flow prototype.
- Whether any low-risk mutation can later receive persistent automation approval depends on the operation and approval models.
- App Store distribution, extensions, and entitlement implications depend on Apple-platform feasibility findings.
- Attachment-specific disclosure and handling may need finer policy after the agent operation contract is known.
- Failure, recovery, and degraded/offline behavior cannot be finalized until Apple platform constraints and agent topology are known.
- How Gmail restricted-scope verification and the 100-user unverified cap should shape early distribution depends on launch posture once v1 success criteria settle.

## Out of scope

- Microsoft 365/Exchange and Proton provider support: planned for v2, not this v1 specification.
- Built-in AI assistant or model hosting.
- Regex, wildcard, or AI-classified access rules.
- Unattended remote-agent access.
- Calendar, contacts management, advanced visual customization, and server-side rule editing.
- Technical architecture, framework selection, storage implementation, build plan, and implementation tickets.
