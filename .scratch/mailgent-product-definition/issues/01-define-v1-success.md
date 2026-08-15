# Define v1 Success and Product Acceptance Boundary

Type: grilling
Status: resolved

## Question

What observable user outcomes and acceptance criteria must the v1 product specification guarantee, and which tempting capabilities are unnecessary for MailGent to deliver its core promise?

## Answer

MailGent v1 succeeds as a **macOS-first agent-safe companion to Apple Mail**, not yet as a replacement daily mail client. A technical or power user must be able to connect Gmail and Yahoo; grant a named local external agent explicit scoped read/search access and draft creation; require in-app approval for mutations; revoke access; and inspect a comprehensive local access log.

Required human surfaces are account connection, scoped search/read, draft inspection and editing, mutation approvals, policy management, audit inspection, and opening the source message in Apple Mail. Optional macOS notifications are configurable by event severity and remain local.

The access log records agent identity, timestamp, query or proposed action, scope used, records exposed, redactions, outcome, and approval result. Access must fail closed when policy or identity is ambiguous.

Full daily-client behavior, iPhone/iPad delivery, built-in AI, Microsoft/Proton, always-on remote agents, and feature parity with Apple Mail are not required for this v1 success boundary.
