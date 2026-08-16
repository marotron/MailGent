# Define Companion Human-Surface Behaviors

Type: grilling
Status: resolved
Blocked by: 05

## Question

For account connection, scoped search/read, draft inspection and editing, mutation approval, policy management, audit inspection, opening messages in Apple Mail, and human-initiated soft delete (Trash) plus hard delete (permanent) for Gmail and Yahoo, what behavior and edge cases must the macOS v1 companion support without drifting into daily-client parity?

Constraint from map: soft delete and hard delete are both agent-proposeable (capability + approval) and also available as direct human UI actions. Empty Trash / bulk purge stays human-only if exposed.

## Answer

v1 human UI is a **companion control plane** beside Apple Mail: connect accounts, review mail agents may touch, approve mutations, manage policy/audit, and perform soft/hard delete. It is not a daily-client replacement.

### Accounts

- Connect, reconnect, and disconnect Gmail and Yahoo via OAuth.
- Multiple accounts; surface sync health (`ok` / `degraded` / `needs reauth`).
- No contacts or calendar sync.

### Search and read

- Unified and per-account search/list; every hit shows source account + placement (ticket 05).
- Humans can read full message/thread bodies in the companion (not grant-limited).
- Open source message in Apple Mail when handoff is available; fail gracefully if not.
- No inbox-zero workflow, filing-first UX, or daily-client composition chrome beyond drafts and approvals.

### Drafts

- Inspect, edit, and discard human or agent drafts.
- Account and From are always visible.
- Send from the companion requires explicit human confirmation (same one-shot gate pattern as agent send proposals).

### Approvals, policy, audit

- In-app approval queue: approve, deny, or edit-then-approve (ticket 08).
- Soft-delete proposals and hard-delete proposals are distinct queue items with matching severity warnings.
- Policy and agent management: pair, trust class, grants, revoke/suspend/forget (ticket 07); authoring UX detail belongs to prototypes.
- Append-only audit browser filtered by agent, time, and action. Export is optional later, not required to lock v1.

### Delete

- Soft delete → Trash: agent-proposeable (capability + approval) and direct human action with confirmation.
- Hard / permanent delete: agent-proposeable (separate capability + approval with stronger confirm) and direct human action with extra confirmation.
- Empty Trash / purge, if exposed in v1, is human-only and confirmed (not an agent proposal type).

### Explicitly out of companion v1

- Daily triage as primary UX, provider-side rule editing, calendar, contacts, and iPhone/iPad delivery (map out of scope).

## Comments

- User approved the recommended companion package in one shot.
- **Superseded (user):** agents may request soft or hard delete; both need human approval. Direct human soft/hard delete remains.
