# Choose Agent Runtime and Cross-Device Topology

Type: grilling
Status: resolved
Blocked by: 03, 04

## Question

Which device owns each local agent session, how do agents discover and connect to MailGent, what crosses devices through iCloud, and how are explicit remote sessions mediated without creating an unattended inbound endpoint?

## Answer

### Session ownership and local discovery

- In v1, MailGent or its user-consented helper owns the live MCP server session. Agents connect to MailGent; they do not launch it.
- Local connectivity is hybrid: prefer UDS/App Group IPC for stronger isolation, with hardened loopback-only HTTP for MCP hosts that require it.
- Both paths require explicit pairing, per-agent credentials and grants, proof of credential possession, immediate revocation, and auditing. A claimed agent name or local process status is never sufficient identity.
- An optional stdio bridge is deferred to a later version.

### Device boundary

- Each Mac independently owns its agent identities, grants, sessions, mailbox cache, credentials, cryptographic keys, approval history, and audit logs.
- iCloud uses an explicit allowlist: appearance/layout, default search/view behavior, and non-sensitive notification preferences.
- Mail, attachments, indexes, account metadata, addresses, folders, smart folders, policies, agent data, sessions, approvals, logs, and keys remain device-local.

### Remote sessions

- A paired remote identity may be remembered, but remote reachability is never permanent.
- The user explicitly opens each session with a lightweight confirmation. Duration choices are 15 minutes, one hour (default), eight hours, or custom up to 24 hours.
- Expiry, explicit stop, logout, revocation, or security reset terminates the session. Brief sleep pauses it and requires Touch ID to resume.
- The selected Mac remains session owner and policy authority. A temporary end-to-end encrypted relay provides reachability but cannot read mailbox content, requests, or responses.
- Mail mutations continue to use their separate approval rules.
- Exact IPC, HTTP, relay, and cryptographic implementation belongs to architecture planning.

## Comments

- v1: MailGent app or its user-consented helper owns the live local session. Agents connect to MailGent; they do not launch it.
- Later version: add an optional stdio bridge for hosts that only support stdio.
- Each Mac independently owns agent identities, grants, active sessions, mailbox cache, credentials, and audit logs. iCloud sync is limited to non-sensitive preferences.
- v1 local connectivity is hybrid: prefer UDS/App Group IPC for stronger local isolation, while offering hardened loopback-only HTTP for MCP hosts that require it. Both paths use explicit pairing, per-agent identity and grants, proof of credential possession, revocation, and auditing; neither trusts a claimed agent name.
- v1 remembers a paired remote identity but never grants permanent remote reachability. The user opens each session with a lightweight confirmation; default duration is one hour, with 15-minute, 8-hour, and custom choices capped at 24 hours. Expiry, explicit stop, logout, revocation, or security reset closes it. Brief sleep pauses it and requires Touch ID to resume. Mail mutations retain their separate approval rules.
- Remote sessions use an end-to-end encrypted, temporary relay. The selected Mac remains session owner and policy authority; the relay provides reachability but cannot read mailbox content, agent requests, or responses. Exact relay technology is deferred to architecture planning.
- iCloud sync uses a strict allowlist for appearance/layout, default search/view, and non-sensitive notification preferences. All mailbox, account, policy, agent, session, approval, audit, and cryptographic data remains device-local.
