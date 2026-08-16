# Prototype Agent Pairing and Finish-Setup

Type: prototype
Status: resolved
Blocked by: 06, 07, 10

## Question

After the user names an agent and picks a trust class, what is the simplest trustworthy flow to finish connecting that agent to MailGent — pairing challenge, per-agent credential, local vs loopback MCP path, copy-paste / host setup help, connection status, and (for `remote`) opening a time-bounded session — without pretending a display name alone is identity?

## Answer

**Ship wizard A as required.** Connection desk B is nice-to-have for inspect/re-pair after first setup. Drop checklist C.

Locked product shape (`examples/prototype-agent-pairing-setup.html`):

1. **After identity + trust class** (issue 10) — finish-setup is a separate connect flow; display name is never identity.
2. **A · Guided wizard (required)** — challenge approve → connection path (prefer UDS / App Group IPC; hardened loopback HTTP when needed; remote relay for `remote`) → per-agent credential + host config snippet / open-in-host → wait for connect (statuses: waiting · paired · connected · needs reauth) → for `remote`, open explicit session (15m / 1h default / 8h / custom ≤24h) → status with revoke credential / suspend / forget.
3. **B · Connection desk (nice-to-have)** — agent list + live panels for the same controls; useful for re-pair, path change, session open/stop, and revoke without re-running the wizard.
4. **Shared rules** — proof of possession on reconnect; no permanent remote reachability; forget destroys credentials (re-pair = new identity); grants stay in issue 10; stdio bridge deferred (ticket 06).

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

## Comments

- Prototype started: `examples/prototype-agent-pairing-setup.html` — three variants (`?view=wizard|desk|checklist`).
  - **A · Wizard** — linear finish-setup after identity+trust: challenge → path → credential/host snippet → wait for connect → remote session (if needed) → status/revoke.
  - **B · Desk** — left agent list; right live panels for challenge, path+host, connect/session, revoke/suspend/forget.
  - **C · Checklist** — progressive requirements with side panel for the active item.
- Shared rules from 06/07: pairing challenge (name ≠ identity), per-agent credential + proof on reconnect, prefer UDS / loopback MCP / remote relay, host config copy + open-in-host stub, statuses waiting·paired·connected·needs-reauth·suspended, remote session durations 15m/1h/8h/custom≤24h, revoke credential / suspend / forget.
- User: A must; B nice-to-have; C dropped.
