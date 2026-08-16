# Define Per-Agent Authorization and Exposure

Type: grilling
Status: resolved
Blocked by: 06

## Question

What are the exact deny-by-default semantics for agent identity, trust class, grants, allow/deny precedence, account and mailbox scopes, address/domain/date selectors, field-level exposure, smart folders, grant duration, revocation, and policy explanation?

## Answer

MailGent authorizes **agent identities**, not models. Deny by default. Effective request:

`identity + class ceiling + data grant + capability + required approval`

Hard delete has no capability and cannot be granted. Exact operations and approval UX belong to ticket 08.

### Agent vs model

- Grants attach to product-agnostic agent identities (Hermes, Cursor, CLI, future hosts).
- A LAN model is an inference backend the agent may use; it is not a MailGent peer.
- MailGent cannot verify which model an agent calls in v1 (no built-in assistant).

### Trust classes (B2)

| Class | Who | Ceiling |
| --- | --- | --- |
| `lan-inference` | Same-Mac agent manually promoted; user declares LAN-only inference | Regular + private scopes |
| `machine-local` | Default for new same-Mac agents | Regular scopes; never private |
| `remote` | Mediated remote session (includes agents on other LAN machines in v1) | Only remote-eligible scopes; active session required |

- No LAN listener; topology from ticket 06 stands.
- Promotion to `lan-inference` is Touch ID–gated, warns locality is unverified, never expands grants. Downgrade immediately disables incompatible grants.

### Scope sensitivity

Every allow grant (direct or smart-folder-backed) is exactly one of:

- **Private** → `lan-inference` only
- **Regular** (default) → `lan-inference` or `machine-local`
- **Remote-eligible** → any class, remote still needs session confirmation

Less-restrictive reclassification is access broadening and requires confirmation.

### Precedence and evaluation

`effective access = class ceiling ∩ active allows − matching denies`

- Deny always wins.
- Per message, not whole thread.
- Immediate re-evaluation on mail or policy change.
- Search, counts, snippets, threads, and errors must not reveal denied messages.

### Selector composition

- Different selector groups: **AND**
- Values within one group: **OR**
- Multiple allows: **union**; denies use same match then subtract

### Account and placement

- Every allow lists at least one account. `All current accounts` is a snapshot; new accounts never join automatically.
- Placement optional; if omitted, other selectors may match anywhere in selected accounts.
- Gmail: any selected label; Yahoo: single folder; canonical virtual Archived selectable.
- New placements not implicit; placement changes re-evaluate immediately.

### Address / domain

- Role-aware `From` / `To` / `Cc` / `Bcc`; optional `Any participant`.
- Normalized addresses only; never display names.
- Domains exact unless `include subdomains`; aliases distinct unless user groups them.

### Date

- Inclusive absolute ranges and rolling windows.
- Provider-authoritative mailbox timestamps (not sender `Date`).
- User local timezone; continuous re-evaluation; per-message in threads.

### Field exposure

Independent groups; nothing else implied:

1. Required locator (account, message id, placement, provider timestamp)
2. Envelope
3. Body / snippet
4. Attachment metadata
5. Attachment content / extracted text
6. Selected headers

Body-off ⇒ no snippet. Metadata ≠ content. Search only readable fields. Omit unavailable fields without redaction hints.

### Smart folders

Named reusable dynamic selectors (not provider placements); allow or deny; classified private / regular / remote-eligible. Narrowing immediate; broadening needs per-grant confirmation; deletion disables dependents (never unrestricted).

### Duration

- Same-Mac: persist until revoked by default; optional session / timed / fixed end.
- Remote: remember definitions; reactivate only with confirmation each user-started session.
- Grant and session expiry: whichever first; block new access; cancel in-flight where practical. Audit remains.

### Revocation

1. Revoke one grant  
2. Suspend agent (config kept)  
3. Forget agent (credentials and assignments destroyed)

Immediate stop; cancel pending mutations; append-only audit; disclosed data cannot be recalled; re-pair = new identity.

### Policy explanation

- Human: class, matching allow/deny, fields, expiry, decision; pre-save counts.
- Agent: own grant summaries only; object deny/missing → generic `not_available`; no rule/count/field/existence leaks. Audit keeps internal reason.

### Data vs capabilities

- Data grant ≠ operation capability and vice versa.
- Both required; mutation approval is an additional gate.
- Capability list and approval behavior deferred to ticket 08.

### Examples

- Trust class option B explainer: `examples/agent-trust-classes-option-b.html`
- Agent vs model: `examples/agent-vs-model-trust.html`

## Comments

- User intent: distinguish agent vs model. Desired trust ladder is LAN model → local (machine) Cursor agent → remote agent. Clarification page: `examples/agent-vs-model-trust.html`. Pending whether Cursor-on-Mac pointed at a LAN model counts as lan-local or machine-local.
- Selected B2 provisionally: product-agnostic `lan-local`, `machine-local`, and `remote` agent classes. Need to define whether `lan-local` describes the agent's location or its claimed model backend without conflicting with the v1 no-LAN-listener topology.
- For v1, the highest class means an agent running on the MailGent Mac that the user declares uses a LAN model. MailGent does not add a LAN listener and cannot verify the model backend; agents on other LAN machines remain mediated remote connections.
- New same-Mac agents start `machine-local`. Promotion to `lan-inference` is manual, Touch ID-gated, and warns that model locality is not verified. Promotion never expands grants automatically. Downgrade immediately disables incompatible grants. Other-LAN-machine agents remain `remote` in v1.
- Class ceilings: `lan-inference` may receive regular and user-marked private scopes; `machine-local` may receive regular scopes and explicitly granted bodies/attachments but never private scopes; `remote` may receive only scopes explicitly marked remote-eligible, never private, and only during an active remote session. Every class remains deny-by-default.
- Effective access is the class ceiling intersected with active allows, minus matching denies. Deny always wins. Evaluation is per message and updates immediately when mail or policy changes. Search results, counts, snippets, threads, and errors must not reveal denied messages.
- Selector composition: different selector groups are ANDed; multiple values within one group are ORed; multiple allow grants form a union; denies use the same matching rules and then subtract.
- Address selectors are role-aware (`From`, `To`, `Cc`, `Bcc`) with an explicit `Any participant` shortcut. Match normalized addresses, never display names. Domains match exactly unless `include subdomains` is selected. Aliases stay distinct unless the user explicitly groups them.
- Date selectors support inclusive absolute ranges and continuously evaluated rolling windows, using provider-authoritative mailbox timestamps rather than sender-controlled `Date` headers. Boundaries use the user's local timezone. Eligibility updates immediately and remains per-message within threads.
- Field exposure is independent: required locator; envelope; body/snippet; attachment metadata; attachment content/extracted text; and selected headers. Nothing else is implied. Body-disabled means no snippet; attachment metadata never grants content. Agents may search only readable fields, and unavailable fields are omitted without revealing redaction hints.
- Smart folders are named reusable dynamic selectors, not provider placements. They may drive allow or deny rules and are classified private, regular, or remote-eligible. Membership updates dynamically. Narrowing applies immediately; broadening linked access requires explicit confirmation for each affected grant. Deletion disables dependent grants rather than making them unrestricted.
- Same-Mac grants persist until revoked by default, with optional session, timed, or fixed-date expiry. Remote grant definitions may be remembered but reactivate only after confirmation for each user-started session. Grant and session expiries both apply; whichever comes first blocks new access and cancels in-flight requests where practical. Audit history remains.
- Revocation has three levels: revoke one grant; suspend an agent while preserving configuration; or forget an agent and destroy its credentials/assignments. Each immediately terminates affected access and cancels pending mutations. Audit history remains append-only. Previously disclosed data cannot be recalled. Re-pairing creates a new identity and never revives old grants.
- Human policy explanations show class ceiling, matching allows/denies, exposed fields, expiry, and final decision, with pre-save counts. Agents may inspect their own effective grant summaries, but object-level missing and denied cases both return generic `not_available`; no hidden rule, count, field, or message existence leaks. Audit retains the exact internal reason.
- Every allow grant selects at least one explicit account. `All current accounts` is a snapshot and never includes future accounts. Placement is optional; Gmail matches any selected label, Yahoo its folder, and canonical virtual Archived is selectable. New placements are not implicit, and placement changes trigger immediate re-evaluation.
- Every direct or smart-folder-backed allow grant is classified exactly one of private (`lan-inference` only), regular (`lan-inference` or `machine-local`), or remote-eligible (any class with active remote-session confirmation). Default is regular. Moving to a less restrictive class is access broadening and requires confirmation.
- Data grants and operation capabilities are separate axes; both are required for a request, mutation approval remains an independent gate, and hard delete has no grantable capability. Exact operations deferred to ticket 08.
