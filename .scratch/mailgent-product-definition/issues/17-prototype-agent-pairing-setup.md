# Prototype Agent Pairing and Finish-Setup

Type: prototype
Status: open
Blocked by: 06, 07, 10

## Question

After the user names an agent and picks a trust class, what is the simplest trustworthy flow to finish connecting that agent to MailGent — pairing challenge, per-agent credential, local vs loopback MCP path, copy-paste / host setup help, connection status, and (for `remote`) opening a time-bounded session — without pretending a display name alone is identity?

## Notes (deferred from policy-authoring prototype)

Policy authoring Variant A (issue 10) keeps **New agent** to identity + trust class only. Real connect UX is explicitly deferred here.

Must cover (tickets 06 / 07):

1. Pairing challenge + user approve (claimed name is never enough)
2. Per-agent credential + proof of possession on reconnect
3. Connection path: prefer UDS/App Group IPC; hardened loopback HTTP for MCP hosts that need it
4. One-time setup help (config snippet / “open in host”) so the agent can reach MailGent
5. Status: waiting · paired · not yet connected · needs reauth
6. For `remote`: open session (duration choices), not permanent reachability
7. Revoke / suspend / forget remain available after pairing (ticket 07)

Out of scope for this ticket: grant/selector authoring (issue 10), mutation approval (issue 11), stdio bridge (later version per ticket 06).
