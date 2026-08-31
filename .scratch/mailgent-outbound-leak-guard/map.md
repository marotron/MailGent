# Outbound leak guard

On-device sanitization of MCP-bound mail **after** grant checks. v1 = heuristics + user custom rules (no Core ML).

## Status

| Phase | Branch | State |
|-------|--------|-------|
| Prototype | `proto/outbound-leak-guard` | **active** — interactive HTML |
| Implementation | `feat/outbound-leak-guard` | not started |

## Prototype

Open in browser (no build):

`.scratch/mailgent-outbound-leak-guard/examples/prototype-outbound-leak-guard.html`

Covers:

- **Grant desk integration** — Scope | Access | Privacy tabs (not a separate settings window)
- Scope: grant placements + field badges + per-row **🛡 scan** leak-guard opt-in
- Privacy tab: master toggle, built-in classes, custom rules
- Literal / wildcard / regex filters with redact vs fake-value replace
- Per replace rule: **tell agent** toggle (stealth vs disclosed sanitized)
- Subject + body hit modes (span vs block whole field)
- Live agent-visible vs human access-log preview
- MCP JSON shape (`subjectAccess`, `leak_guard` reason)
- **ⓘ on-demand help** — accordion panels (one open at a time) on Scope, Access, Privacy, built-ins, preview

**Stop and ask** before train work on `feat/outbound-leak-guard`.

## Locked product (from planning)

- Scan **subject + body only**; other headers untouched in v1
- **Opt-in allowlist** of mailboxes/placements; empty = no scan
- Grant denial vs autodetect must stay visually and semantically distinct
- Fail-open on detector timeout (alpha)

## Train (after prototype sign-off)

See plan: outbound leak guard v1 — policy JSON, MailStore detectors, AgentReadAPI wire, settings tab, access log UX, 0.2.0.

## Links

- [01 · Prototype](issues/01-prototype-leak-guard.md)
- [Agent operation contract](../mailgent-product-definition/issues/08-define-agent-operation-contract.md) — amend for `sanitized` + `leak_guard`
- Prior wayfinding: Aug 2026 outbound leak-guard session
