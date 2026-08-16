# Define Security, Audit, and Recovery Behavior

Type: grilling
Status: resolved
Blocked by: 07

## Question

What product-visible guarantees must v1 provide for credential protection, device lock and loss, agent authentication, fail-closed access, grant revocation, comprehensive append-only access events, audit retention and inspection, configurable local notifications by severity, destructive-action recovery, and clear failure states?

## Answer

### Credentials and device security

- OAuth tokens and agent keys remain in Keychain and never sync through iCloud.
- App quit, logout, or screen lock pauses agent sessions. Remote sessions require Touch ID to resume (ticket 06).
- No cloud mailbox or agent recovery exists. For device loss, user revokes provider OAuth and forgets agents on a replacement Mac.
- A local security reset destroys agent identities, sessions, grants, and keys. Audit remains when the local disk remains available; it is lost with that disk.

### Agent authentication and failure

- Pairing plus proof of key possession is mandatory (ticket 06).
- Access fails closed for expired grants or sessions, suspended/forgotten agents, policy denial, offline providers, or cache states that cannot support a safe mutation.
- Reads may use last-known local cache and must be marked stale. Mutations never report success until provider-confirmed.

### Revocation

- Grant revocation, suspension, and forgetting an agent remain immediate (ticket 07).
- Affected access stops and pending proposals cancel. Previously disclosed data cannot be recalled.

### Audit

- Local append-only events record authentication, grant changes, high-level reads/searches, mutation proposals, approvals, denials, revocations, session open/close, and security resets.
- Audit entries cannot be silently edited or deleted in v1.
- Retention is manual-purge only: records remain until user explicitly purges them with Touch ID. Automatic max-age retention is deferred.
- Human audit UI supports filtering by agent, time, and action. Agents cannot read another agent’s audit history.

### Notifications

- Notifications remain local and user-configurable by severity: authentication failures, pending approvals, revocations, and security resets.
- Notifications contain no mail content by default.

### Destructive recovery

- Soft delete remains recoverable through provider Trash behavior.
- Hard delete, empty Trash/purge, forget-agent, and security reset require confirmation. Forget-agent and security reset also require Touch ID.
- MailGent provides no undo beyond provider Trash recovery.

### User-visible failures

- `needs reauth`
- `sync degraded`
- `agent suspended`
- `remote session expired`
- `offline — reads stale / mutations blocked`

### Comments

- User approved this v1 package in one shot.
