# Merge Local-Read Train

Type: task
Status: resolved
Blocked by: 05, 07

## Question

Is `train/local-read` ready to merge to `main` as the first usable product, with prototypes captured as pointers and OAuth left as a later train that keeps local-read as a source?

## Context

Merge `train/local-read` → `main` when tickets 01–07 are green (06 resolved with B; 07 DraftLedger on the train).

- Capture prototypes as primary sources (branch pointers on issues 04 and 06).
- Next train `train/oauth`: Gmail API + Yahoo IMAP OAuth, provider-faithful mailbox model, mutation approvals, richer grants. Local-read remains a source, not a discarded bridge.
- Do not commit live mail, FDA bookmarks, or pairing secrets.

Finish `feat/07-draft-ledger` before this merge.

## Verify

Train merged; prototype branches recorded on their issues; OAuth not started on this train; local-read kept.

YAGNI: do not start OAuth work on the merge PR.

## Inputs

- [05 · MCP Read, Pairing, Grants, Audit](05-mcp-pairing-grants-audit.md) — first-ship acceptance slice
- [06 · Draft Outbound Prototype](06-draft-outbound.md) — B won; ledger required
- [07 · Draft Ledger Seam + MCP](07-draft-ledger.md) — must land before merge

## Answer

Yes. `train/local-read` fast-forwarded onto the ticket-07 tip and merged to `main` (`8720b8a`). Local-read first ship is on `main`.

- Prototypes stay off `main`: `proto/companion-read-ui` @ `b7252e6`; `proto/draft-outbound` @ `52cb9e0`.
- Throwaway draft A/B UI removed from the train before merge; agent path is MCP `create_draft` / `update_draft` + in-memory DraftLedger.
- OAuth not started; next train remains `train/oauth` with local-read kept as a source.

## Comments

- 2026-08-20 — Claimed; FF `feat/07-draft-ledger` → `train/local-read` → `main`; capture proto tips; strip draft prototype from train.
- 2026-08-20 — Resolved. First usable local-read product on `main`.
