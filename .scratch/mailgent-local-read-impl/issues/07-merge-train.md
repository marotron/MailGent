# Merge Local-Read Train

Type: task
Status: open
Blocked by: 05

## Question

Is `train/local-read` ready to merge to `main` as the first usable product, with prototypes captured as pointers and OAuth left as a later train that keeps local-read as a source?

## Context

Merge `train/local-read` → `main` when tickets 01–05 (and 06 if the ledger won) are green.

- Capture prototypes as primary sources (branch pointers on issues 04 and 06).
- Next train `train/oauth`: Gmail API + Yahoo IMAP OAuth, provider-faithful mailbox model, mutation approvals, richer grants. Local-read remains a source, not a discarded bridge.
- Do not commit live mail, FDA bookmarks, or pairing secrets.

Ticket 06 does not block this merge unless variant B (draft ledger) won and `feat/07-draft-ledger` is still open — then finish that feat first.

## Verify

Train merged; prototype branches recorded on their issues; OAuth not started on this train; local-read kept.

YAGNI: do not start OAuth work on the merge PR.

## Inputs

- [05 · MCP Read, Pairing, Grants, Audit](05-mcp-pairing-grants-audit.md) — first-ship acceptance slice
- [06 · Draft Outbound Prototype](06-draft-outbound.md) — blocks merge only if ledger won
