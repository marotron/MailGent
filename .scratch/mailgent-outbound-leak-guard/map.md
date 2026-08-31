# Outbound Leak Guard

Label: wayfinder:map

## Destination

Ship **on-device outbound leak guard v1** for paired agents: heuristics + custom rules (no Core ML), opt-in per placement, Grant Desk authoring, MCP access flags, and access-log overlays. Stop when `feat/outbound-leak-guard` merges to `main` as **0.2.0**.

**Reached.** Implementation complete on `feat/outbound-leak-guard` (Phases 1–7). Ready to merge and tag `v0.2.0`.

## Notes

- Pipeline order (locked): authenticate → grant filter/caps → leak guard (subject + body only, opted-in placements) → serialize → audit.
- Skip scan when: master off, empty scope allowlist, placement not opted in, field not granted, detector error (alpha fail-open).
- Policy file: `~/Library/Application Support/MailGent/sensitive-filter.json`.
- UI lives in Grant Desk only (Scope / Access / Privacy tabs). No changes to field badge chips or hatch-denied styling.
- Prototype: [`examples/prototype-outbound-leak-guard.html`](examples/prototype-outbound-leak-guard.html).

## Decisions so far

- [Prototype leak guard](issues/01-prototype-leak-guard.md) — HTML prototype for Grant Desk Privacy tab, built-ins, custom rules, hit modes
- [MCP leak guard contract](issues/02-mcp-leak-guard-contract.md) — `subjectAccess` / `bodyAccess`, `leak_guard` reason, `sanitizedRules`, stealth replace

## Implementation (shipped in 0.2.0)

| Layer | Files |
| --- | --- |
| Engine | `OutboundLeakGuardPolicy.swift`, `BuiltInHeuristicDetector.swift`, `CustomRuleDetector.swift`, `OutboundLeakGuard.swift`, `SanitizedField.swift` |
| Read path | `AgentReadAPI.swift`, `AuditJSON.swift`, `AuditLog.swift`, `LoopbackMCPServer.swift` |
| Persistence | `AgentBridge.swift` → `sensitive-filter.json` |
| UI | `GrantDeskView.swift`, `LeakGuardPrivacyPane.swift`, `AccessLogView.swift`, `CompanionBits.swift` |
| Tests | `OutboundLeakGuardTests.swift`, `AgentReadAPITests.swift`, `LoopbackMCPServerTests.swift` |

## Out of scope (v1)

- Core ML
- Scanning From/To/Cc/Date/attachments
- Separate settings window
- Prototype HTML styling / custom shield icon

## Branches

| Branch | Parent | Merge target |
| --- | --- | --- |
| `feat/outbound-leak-guard` | `main` | `main` → tag `v0.2.0` |
