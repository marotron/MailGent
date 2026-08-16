# Prototype Companion Search and Review Navigation

Type: prototype
Status: resolved
Blocked by: 05

## Question

What macOS companion information architecture lets a user search and review unified or per-account mail, inspect and edit agent drafts, process approvals, inspect policies and audit events, and open source messages in Apple Mail while preserving source-account clarity?

## Answer

**Default IA: control-first (Variant C).** Landing surface is a control center (needs attention, sync health, recent agent activity) with deliberate navigation into mail search, drafts, approvals, policies, and audit.

Settings may change the default home later among the three prototype modes:

1. **Control-first** (default) — safety / agent state first
2. **Search-first** — unified/per-account find-and-review first
3. **Review desk** — shared queue of search hits, drafts, and proposals beside an inspector

Shared across modes (locked by tickets 05 / 12):

- Every mail hit shows source account + placement
- Open in Apple Mail when handoff available
- Approvals, policy, and audit remain first-class destinations, not buried
- Companion stays a control plane, not a daily client

Prototype: `examples/prototype-companion-navigation.html`

## Comments

- User prefers C; wants a settings option to switch default home later among A/B/C.
