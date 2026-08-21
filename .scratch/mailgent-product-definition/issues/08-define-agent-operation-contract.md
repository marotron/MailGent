# Define Agent Operations and Redaction Contract

Type: grilling
Status: resolved
Blocked by: 05, 07

## Question

Which resources and operations does MailGent expose to agents, how are searches bounded and paginated, how is inaccessible data omitted or redacted without leaking it through metadata, and how do draft and mutation proposals behave under partial access?

Constraint from map: agents may propose soft delete → Trash or hard/permanent delete when granted the matching capability; both are approval-gated. Soft delete is recoverable; hard delete needs stronger confirmation.

## Answer

Every agent request still requires `identity + class ceiling + data grant + capability + required approval` (ticket 07). This ticket locks the operation surface and redaction behavior.

### Resources

Agents may address only:

- Granted accounts
- Messages and same-account threads
- Drafts owned by a granted account
- Placements (Gmail labels / Yahoo folder / canonical virtual Archived)
- Attachments when field grants allow
- The agent’s own effective grant summary

Soft-delete and hard-delete are separate capabilities (not a single undifferentiated `delete`).

### Read operations (capability only; no approval)

- `list` / `search` / `get` message or thread
- `list` placements in granted accounts
- `get` attachment metadata or content when field-granted
- `list` own grants

### Write operations

| Operation | Gate |
| --- | --- |
| Create / update / discard draft | Capability only |
| Propose send | Capability + human approval |
| Propose soft delete → Trash | Capability + human approval |
| Propose hard / permanent delete | Capability + human approval (stronger confirm in UI) |
| Propose move / label / archive / mark read-unread / star | Capability + human approval |

### Search and pagination

- Search runs only over fields the agent can read under active grants.
- Results, counts, snippets, and threads are deny-filtered; denied messages never appear and never inflate counts.
- Cursor pagination; default page size ~25, hard max 100.
- Counts reflect visible hits only.

### Redaction / omission

- Denied, missing, and no-capability cases all return the same generic `not_available` to the agent.
- Unavailable fields are omitted; no `[redacted]` stubs or empty placeholders that imply hidden content.
- Threads never include ghost entries for denied sibling messages.
- Human UI and append-only audit retain the exact internal reason.

### Drafts under partial access

- Creating a draft requires explicit account and From identity (ticket 05).
- Drafts may cite only messages the agent can currently read.
- Blocked cites are rejected individually; the rest of the draft may proceed unless a blocked cite is required for the request.
- A send proposal presents the human with the full draft text and recipients; approval is per proposal.

### Approvals

- Companion in-app queue: approve, deny, or edit-then-approve.
- Soft-delete proposals warn that mail moves to Trash (recoverable).
- Hard-delete proposals use a stronger permanent-purge warning and confirmation before approve.
- Optional local notifications follow existing severity preferences.
- No persistent auto-approve / automation approval in v1.
- Grant or session expiry cancels pending proposals; audit remains.

## Comments

- User approved the recommended v1 package in one shot: resources, read/write gates, search/pagination, omission-without-leak, draft cite rules, one-shot approvals, no v1 persistent automation, hard delete absent from agent surface.
- **Superseded (user):** agents may request soft delete or hard delete; both still require human approval. Soft delete purpose = recoverable remove. Hard delete = permanent purge with stronger confirm.
- **Superseded (user, 2026-08-21):** body field denial is **not** collapsed into generic `not_available` / empty string. MCP `get` must return `bodyAccess: "not_granted"` (and omit `body`) so agents know to ask for a grant upgrade rather than summarize as empty mail. Message-level deny and missing content still omit without redaction stubs.
