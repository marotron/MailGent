# Define the Canonical Mailbox Model

Type: grilling
Status: resolved
Blocked by: 02

## Question

How should MailGent represent accounts, identities, threads, messages, Gmail labels, Yahoo folders, drafts, sent mail, and cross-account search so unified and separate views remain predictable without erasing provider-specific behavior?

Constraint from map: canonical ops must distinguish soft delete (Trash) from hard/permanent delete. Both may be agent-proposed with approval when granted (ticket 08); humans may also delete directly.

## Answer

MailGent keeps **provider-faithful objects** under a thin product vocabulary. Accounts stay separate. Messages and drafts belong to exactly one account and identity. Threads never cross accounts. Unified and separate views show the same objects; unified only merges listing/search hits.

### Placement vs flags (B1)

- **Placement** = where mail lives (Gmail labels / Yahoo folder). Gmail may have many placements; Yahoo has exactly one.
- **Flags** = state (read/unread, starred/flagged, …). Both providers allow many flags with the current placement.
- UI may say “labels.” Agent/API contract always distinguishes placement vs flags. Illegal Yahoo second placement fails closed with a clear error.

### Archive (A1)

- Product verb `archive` maps per provider:
  - Gmail → remove `INBOX` only (no stored Archive label).
  - Yahoo → move to Archive folder.
- Product view `Archived` is **virtual**: Gmail = not Inbox/Trash/Spam (and not Drafts as needed); Yahoo = placement Archive. Never invent a Gmail system/user Archive label as source of truth.

### Threads and drafts

- Threads are per-account only. No cross-account mega-threads.
- Drafts are owned by one account; send uses that account’s chosen From identity. Agents must specify account and From when creating drafts.

### Delete (C1 + prior lock)

- Soft delete → Trash and hard/permanent delete are distinct ops for Gmail and Yahoo.
- Both may be agent-proposed when capability + approval allow (ticket 08).
- Empty Trash / bulk purge, if exposed, remains a human-only companion action.

### Unified search (D1)

- Unified search = ranked merge of per-account hits.
- Every result shows source account + placement.
- No fake shared folder or cross-account thread. Separate view = same objects filtered to one account.

### Examples

- Walkthrough of provider differences: `examples/mailbox-model-problem.html`
- Decision options locked here: `examples/mailbox-model-remaining-challenges.html` → A1, B1, C1, D1

## Comments

- **Superseded (user):** soft and hard delete both agent-proposeable with approval (ticket 08); empty Trash / bulk purge stays human-only if exposed.
