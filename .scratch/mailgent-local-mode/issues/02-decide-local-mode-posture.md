# Decide Local-Mode Product Posture

Type: grilling
Blocked by: 01
Status: resolved

## Question

After research: keep the proposed **poll → analyze → copy-paste** loop as (a) a temporary bridge until OAuth, (b) a lasting offline/fallback feature, or (c) do not ship?

## Context

The proposed loop reads Apple Mail's `~/Library/Mail` on a cadence, maintains a local message list, and on new `.emlx` reads and analyzes for MailGent search/read. Outbound is copy-paste only (no Mail-store writes). This is a companion posture, not a replacement client.

## Grilling criteria

- Does the read path hold after ticket 01's findings on TCC, format stability, and completeness?
- Is copy-paste a sufficient outbound path for v1 users, or does it break the value proposition?
- Temporary bridge vs lasting fallback: different maintenance cost and UX implications — which fits v1 better?
- Does this require any v1 spec amendments? If so, which sections?
- Are there scenarios where this should simply not ship (risk, effort, poor fit)?

## Inputs

- [01 · Research ArchMail and Apple Mail On-Disk Viability](01-research-archmail-ondisk-viability.md) — must be resolved first.

## Answer

**Lasting first-ship source.** Apple Mail local-read (`~/Library/Mail`) is how v1 ships. Gmail/Yahoo OAuth stays in the locked spec and starts as the **next train**. Local-read remains after OAuth as an offline / Apple Mail source — not a throwaway pre-OAuth sidecar, not a no-ship.

**Read path holds** after [01](01-research-archmail-ondisk-viability.md): ArchMail-style read is viable with Full Disk Access or a security-scoped bookmark; incremental via FSEvents while running plus an on-open sweep; no Envelope Index; no store writes; partial and undownloaded mail must be surfaced, never treated as full. Working distribution for this train: Developer ID + notarization + FDA. MAS sandbox is hostile.

**Outbound deferred.** First ship is local-read plus agent **read / search / get** only. No Mail-store writes, no AppleScript, no `mailto:`. Copy-paste vs a MailGent-owned versioned draft ledger is decided later, after that read+MCP prototype exists. The v1 spec does not name a send path for local-read yet.

The proposed **poll → analyze → copy-paste** loop is therefore kept only on the **read** side (poll/watch → index → search/read). The copy-paste half is not locked.

**v1 spec amendments** (see [Lock MailGent v1 Product](../../mailgent-product-definition/map.md)):

- Replace “Apple Mail local-read as a possible temporary source” with: first ship = Apple Mail local-read; OAuth is the next train; local-read stays.
- First-ship agent surface is a subset of the locked v1 contract: one paired `machine-local` agent, account + mailbox allows, read ops only, append-only audit. Mutation approvals, send, drafts, remote sessions, smart folders, and private scopes wait.
- Ticket 16 (MAS vs Developer ID under provider caps) remains open for the OAuth era; this train’s working assumption is Developer ID + FDA.

**Do not ship?** No. Research held; companion posture (not a Mail.app replacement) keeps Guideline 5.2.5 lookalike risk in check; completeness gaps are product-visible.

## Comments

- 2026-08-19 — Lasting first-ship source chosen: Apple Mail local-read is how v1 ships; OAuth is additive later; local-read stays. Not a throwaway pre-OAuth sidecar, not a no-ship. Outbound (copy-paste vs ledger) still open.
- 2026-08-19 — Outbound deferred: first ship is read/search/get only. Copy-paste vs MailGent draft ledger decided after the read+MCP prototype. Ticket resolved.
