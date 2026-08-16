# Prototype Agent Mutation Approval

Type: prototype
Status: resolved
Blocked by: 08

## Question

What is the simplest trustworthy in-app flow for reviewing, editing where applicable, approving, rejecting, expiring, and auditing individual or clearly bounded batches of agent-proposed mail mutations across Apple devices?

Constraint from map: agents may propose soft delete → Trash or hard/permanent delete; both need human approval. Empty Trash / bulk purge stays human-only if exposed.

## Answer

**Ship all three IAs.** Queue A for list+inspect; Focus B for one-at-a-time; Batch C for clearly bounded multi-approve.

Locked product shape (`examples/prototype-mutation-approval.html`, `?view=queue|focus|batch`):

1. **Shared mutation rules** — Approve / deny / edit-then-approve. Soft delete → Trash and hard/permanent delete both agent-proposeable; both need human approval. Hard delete gets stronger warning + confirm + solid-red approve CTA. No persistent auto-approve. Grant or session expiry cancels pending proposals; audit remains. Open in Apple Mail available from the proposal.
2. **A · Queue + inspector** — Pending list with type filters; inspector shows agent, account, placement, requested time, expiry, targets or mail-compose preview (edit where applicable), then Deny / Open in Apple Mail / Approve.
3. **B · Focus** — One pending proposal at a time with Deny / Skip / Approve; same warnings and edit-then-approve path.
4. **C · Batch desk** — Multi-select table for a clearly bounded set (same-agent helper); deny or approve selected; inline edit where applicable; hard-delete confirm still gates purge in the selection.

Empty Trash / bulk purge remains human-only if exposed (not an agent batch path).

## Comments

- Prototype started: `examples/prototype-mutation-approval.html` — three variants (A queue+inspector, B one-at-a-time, C batch desk). Shared rules: approve / deny / edit-then-approve, soft + hard delete proposals, simulate grant/session expiry, no auto-approve, Apple Mail stub.
- Related exploration: `examples/prototype-thread-preview-compose.html` — targets/preview rendered in mail-compose chrome (From/To/Subject/attachments + body clamped 2–3 lines with Show more). Variants via `?variant=A|B|C`.
- Folded variant A into `examples/prototype-mutation-approval.html` target preview (compose cards, 3-line clamp + Show more).
- **Model update:** soft and hard delete both agent-requestable with approval; prototype queue includes both proposal types with distinct warnings.
- User: permanent-delete approve CTA solid red (distinct from Deny outline).
- User: ship A + B + C.
