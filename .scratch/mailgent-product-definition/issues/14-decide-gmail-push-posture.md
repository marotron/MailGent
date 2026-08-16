# Decide Gmail Push Posture Under Device-First

Type: grilling
Status: resolved
Blocked by: 03

## Question

Given that Gmail real-time push requires Cloud Pub/Sub and a renewing `users.watch`, while MailGent forbids a cloud that reads mailbox content, should v1 be polling/history-sync only, or allow a content-blind push relay that receives only `emailAddress`/`historyId` and never message bodies?

## Answer

**v1 chooses polling / history sync only (Option A).** No Gmail Pub/Sub push relay in v1.

### Gmail

- Sync via foreground companion and/or user-consented helper using poll + Gmail `history` APIs.
- No Cloud Pub/Sub topic, webhook, or `users.watch` renewal service in the v1 product surface.
- Near-realtime lag is accepted to keep MailGent free of a mail-related cloud dependency.

### Yahoo

- Sync via IMAP IDLE and/or poll on the same consented local helper. No MailGent mail-content cloud.

### Shared rules (ticket 13)

- Reads may use last-known local cache and must be marked stale when offline or behind.
- Mutations never report success until provider-confirmed.

### Deferred

- A content-blind push relay (emailAddress / historyId only, never bodies) remains a later-version option if polling lag becomes a product problem.

### Comments

- User selected Option A for v1.
