# Research Gmail and Yahoo Integration Constraints

Type: research
Status: resolved

## Question

Using first-party documentation, what authentication, mail APIs or protocols, push/sync capabilities, quotas, review requirements, and account-model differences constrain a v1 Apple-platform client supporting Gmail and Yahoo?

## Answer

**Gmail:** Prefer Gmail API + OAuth 2.0 (PKCE / ASWebAuthenticationSession); avoid IMAP/SMTP as primary path — forces restricted `https://mail.google.com/` and fails minimum-scope review for ordinary MUAs. Read/modify/compose scopes are restricted → brand + restricted verification, 100-user cap until approved; CASA if restricted data hits servers. Push needs Cloud Pub/Sub + `users.watch` (≤7-day renew) → conflicts with pure device-first unless polling-only. Quotas: 6,000 units/user/min; send ~500/day consumer, ~2,000 Workspace. Email clients are an approved use case; Limited Use bans ads/third-party transfers and foundational-model training.

**Yahoo:** No proprietary Mail API — IMAP/SMTP OAuth (`mail-r`/`mail-w`) after commercial access approval (scopes not self-serve). IDLE + CONDSTORE; handle MESSAGELIMIT/UIDONLY; IDLE omits deletes. App passwords exist but OAuth is the modern path. Separate OAuth clients for Yahoo vs AOL.

**v1 product:** Start Yahoo access application early; plan Gmail API not IMAP; keep mailbox bodies/tokens on-device to reduce CASA/Yahoo transfer risk; abstract labels vs folders; treat remote agents receiving mail content as policy-sensitive. Soft delete (Trash) may be agent-proposed with approval; hard/permanent delete is human-UI-only for Gmail and Yahoo.

Full findings (cited): [../research/gmail-yahoo-integration.md](../research/gmail-yahoo-integration.md)
