# Research: Gmail and Yahoo Integration Constraints (Apple v1)

**Question:** Using first-party documentation, what authentication, mail APIs or protocols, push/sync capabilities, quotas, review requirements, and account-model differences constrain a v1 Apple-platform client supporting Gmail and Yahoo?

**Access date for all citations unless noted:** 2026-08-15  
**Platforms in scope:** macOS, iOS, iPadOS  
**Out of scope:** Microsoft 365/Exchange, Proton

---

## 1. Decision-oriented summary

| Topic | Confirmed constraint for MailGent v1 |
| --- | --- |
| Gmail access path | Prefer **Gmail API + OAuth 2.0** with least-privilege restricted scopes (`gmail.modify` / `gmail.readonly` + compose/send as needed). Avoid IMAP/SMTP unless permanent-delete-bypass-trash is required — IMAP/SMTP forces `https://mail.google.com/` and fails minimum-scope review if used for ordinary client features. |
| Yahoo access path | **No proprietary Mail REST API** for third parties. Access is **IMAP + SMTP with OAuth 2.0** (`mail-r` / `mail-w`), after Yahoo **approves** commercial developer access. App passwords exist for clients that do not use Yahoo branded sign-in — weaker UX/security; OAuth is the intended path for a modern client. |
| Auth UX on Apple | Use system browser / **ASWebAuthenticationSession** (or Google’s Sign In with Google iOS SDK for Gmail). Installed apps are public clients: **PKCE**, no embedded client secret in the app binary for Google. Yahoo token exchange docs assume `client_id` + `client_secret` — store secret carefully (Keychain / backend) or clarify with Yahoo whether native public-client patterns are allowed for approved mail apps. |
| Push / sync | Gmail real-time push = **Cloud Pub/Sub** → webhook or pull on a **backend**; `users.watch` must be renewed ≤ every 7 days. Device-only polling / history sync remains required as fallback. Yahoo push = **IMAP IDLE** (+ CONDSTORE / HIGHESTMODSEQ / All Mail); IDLE does not report deletes/expunge. |
| Review / launch risk | Gmail: built-in email client is an **approved use case**, but read/modify/compose scopes are **restricted** → brand + restricted-scope verification; **100-user cap** until verified; **CASA** if restricted data is stored/transmitted on servers. Yahoo: mail scopes **not self-serve**; apply via Sender Hub; policy review + security bar. |
| Account models | Gmail: consumer `@gmail.com` vs Google Workspace (admin API allowlists, domain policy can block the app). Labels (many-to-many), not folders. Yahoo/AOL share identity infra but need **separate OAuth client credentials per namespace**; folder model via IMAP SPECIAL-USE. |
| Agent / device-first tension | Google Limited Use + Yahoo “Use of Data” both forbid transferring mailbox content to third parties except for the approved user-facing app. **On-device agent reads** fit better than **remote agents receiving mail bodies**. Any MailGant cloud that sees mailbox content for push or agent mediation triggers Google CASA and Yahoo policy scrutiny. |

---

## 2. Gmail — confirmed facts

### 2.1 Authentication

- Gmail API and IMAP/SMTP for third-party clients use **OAuth 2.0**. Personal Gmail no longer supports sharing Google username/password with third-party clients; users should use “Sign in with Google.” ([Gmail Help — Add Gmail to another email client](https://support.google.com/mail/answer/7126229))
- For iOS & desktop installed apps, Google documents the **authorization code + PKCE** flow; apps are treated as unable to keep secrets; recommend system browser / Sign In with Google iOS SDK. ([OAuth 2.0 for iOS & Desktop Apps](https://developers.google.com/identity/protocols/oauth2/native-app))
- IMAP/POP/SMTP XOAUTH2 uses scope **`https://mail.google.com/`**. Apps must show full utilization of that scope or migrate to Gmail API with granular scopes. ([Gmail XOAUTH2](https://developers.google.com/gmail/imap/xoauth2-protocol))
- Google Workspace domain-wide delegation for IMAP may use `https://www.googleapis.com/auth/gmail.imap_admin` (admin/service-account pattern — not the personal multi-account MUA model). ([Gmail XOAUTH2](https://developers.google.com/gmail/imap/xoauth2-protocol))

### 2.2 APIs / protocols

- **Gmail API** is the REST surface for read, compose, send, labels, drafts, history, attachments, etc. ([Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes); [Usage limits](https://developers.google.com/workspace/gmail/api/reference/quota))
- **IMAP** remains available and, for personal Google Accounts as of Jan 2025, IMAP access is always on (no user toggle). Folder size limits may still apply in IMAP settings for Workspace or user-configured limits. ([Gmail Help — Add Gmail to another email client](https://support.google.com/mail/answer/7126229))
- Organization model is **labels**, not exclusive folders: many-to-many between labels and messages/threads; system labels include `INBOX`, `TRASH`, `STARRED`, categories, etc. ([Manage labels](https://developers.google.com/workspace/gmail/api/guides/labels))
- Scope sensitivity for a full client (confirmed restricted unless noted):
  - Restricted: `gmail.readonly`, `gmail.modify`, `gmail.compose`, `gmail.insert`, `gmail.metadata`, `gmail.settings.*`, `https://mail.google.com/` ([Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes); [Restricted scopes list](https://support.google.com/cloud/answer/13464325))
  - Sensitive (not restricted): `gmail.send` ([Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes))
  - Non-sensitive: `gmail.labels` (and add-on-specific scopes) ([Gmail API scopes](https://developers.google.com/workspace/gmail/api/auth/scopes))
- Google FAQ: IMAP or joint IMAP/SMTP requires `https://mail.google.com/` and restricted verification; if the app does not need permanent delete bypassing Trash, reviewers expect migration to Gmail API with narrower scopes. SMTP-only with full mail scope violates minimum-scope policy — use `gmail.send` instead. ([OAuth verification FAQ — IMAP/SMTP](https://support.google.com/cloud/answer/13463817))

### 2.3 Push / sync

- Full sync: `messages.list` + batched `messages.get`; store latest `historyId`. Partial sync: `history.list` with `startHistoryId`. History usually available ≥ ~1 week; if `startHistoryId` is too old → HTTP 404 → full resync. ([Synchronize clients](https://developers.google.com/workspace/gmail/api/guides/sync))
- Push: Gmail API **server** push via **Cloud Pub/Sub**. Client calls `users.watch` with a topic; renew **at least every 7 days** (recommend daily). Notifications carry `emailAddress` + `historyId` only — then call `history.list`. Max ~1 notification/sec/user; messages can be delayed/dropped → must poll as fallback. ([Push notifications](https://developers.google.com/workspace/gmail/api/guides/push))
- Implication: true Gmail push is not a pure on-device capability; it needs a Google Cloud project + Pub/Sub subscription (push webhook or pull).

### 2.4 Quotas and sending limits

**API quota units** ([Usage limits](https://developers.google.com/workspace/gmail/api/reference/quota)):

| Limit | Value |
| --- | --- |
| Per minute per project | 1,200,000 units |
| Per minute per user per project | 6,000 units |
| Daily billing threshold per project | 80,000,000 units (no increase; charges planned later in 2026 with ≥90 days notice) |
| Recipients per API message | 500 |

Example method costs: `messages.get` 20, `threads.get` 40, `history.list` 2, `messages.send` / `drafts.send` 100, `watch` 100. ([Usage limits](https://developers.google.com/workspace/gmail/api/reference/quota))

**Account sending limits** (shared across web, API, SMTP):

- Consumer / standard Gmail: ~**500 messages/day**; >500 recipients in one message also hits the limit. ([Gmail Help — Limits](https://support.google.com/mail/answer/22839); [Bounced mail](https://support.google.com/mail/answer/6596))
- Google Workspace paid: **2,000 messages/day** per user (trial lower); Gmail API recipients/message **500**; SMTP/IMAP send recipients/message **100**. ([Workspace sending limits](https://support.google.com/a/answer/166852))
- Concurrent IMAP: up to **15** email clients per account; “Too many simultaneous connections” otherwise. ([Gmail Help — Add Gmail…](https://support.google.com/mail/answer/7126229))

### 2.5 Review / verification

- Unverified apps requesting sensitive/restricted scopes: **100 new-user cap** (lifetime of project); then sign-in disabled. ([OAuth FAQ](https://support.google.com/cloud/answer/13463817))
- Verification types (estimates, not guarantees): Brand 2–3 business days; Sensitive ~10 business days; Restricted ~6 weeks (+ security assessment). ([OAuth FAQ](https://support.google.com/cloud/answer/13463817))
- Restricted verification requires: appropriate app type, demo video of OAuth + features, Limited Use compliance, minimum scopes justification, and security assessment when applicable. ([Verification requirements](https://support.google.com/cloud/answer/13464321); [Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification))
- **Approved Gmail use case #1:** “Built-in and web email clients that allow users to compose, send, read, and process email via a user interface.” ([Workspace user data & developer policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy))
- Limited Use: no advertising, no data brokerage, no training foundational/AI models on Google user data; transfers only with narrow exceptions; humans may not read mailbox data without explicit user agreement (except security/legal). Personalized on-device models for the user’s feature are distinguished from foundational models. ([Workspace policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy); [OAuth FAQ — Limited Use / AI](https://support.google.com/cloud/answer/13463817))
- Security: restricted-scope apps must encrypt tokens/data at rest, use modern TLS, follow CASA; apps that **store or transmit restricted-scope data on servers** must complete annual third-party security assessment. ([Workspace policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy); [Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification))
- Exceptions to verification (personal use, testing, internal Workspace-only, etc.) do **not** cover a public App Store mail client. ([Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification))

### 2.6 Account-model differences (Gmail)

| Dimension | Consumer Google Account | Google Workspace |
| --- | --- | --- |
| Consent | End-user OAuth | End-user OAuth **and** possible admin API allowlist / block of OAuth client IDs |
| Admin controls | N/A | Admins can restrict third-party apps; prefer verified apps; may need OAuth client ID published for IT allowlisting |
| Domain policy errors | Rare | `domainPolicy` / blocked third-party access possible |
| Delegation / settings.sharing | Limited | Settings.sharing and some delegate ops admin/service-account oriented |
| Sending limits | ~500/day | Up to 2,000/day (paid) |
| IMAP folder size limits | User setting may apply | Admin/workspace may hide Forwarding and POP/IMAP tab |

Sources: [Google Workspace OAuth considerations](https://developers.google.com/identity/protocols/oauth2/production-readiness/google-workspace); [Auth overview](https://developers.google.com/workspace/guides/auth-overview); [Handle errors](https://developers.google.com/workspace/gmail/api/guides/handle-errors); [Sending limits](https://support.google.com/a/answer/166852); [Gmail Help IMAP](https://support.google.com/mail/answer/7126229).

---

## 3. Yahoo — confirmed facts

### 3.1 Authentication

- Yahoo documents **OAuth 2.0 Authorization Code** grant; OpenID Connect for identity. Auth endpoint `https://api.login.yahoo.com/oauth2/request_auth`; token endpoint `https://api.login.yahoo.com/oauth2/get_token`. ([Yahoo OAuth 2.0 Guide](https://developer.yahoo.com/oauth2/guide/); [OpenID Connect Getting Started](https://developer.yahoo.com/oauth2/guide/openid_connect/getting_started.html); discovery document embedded in [Sender Hub IMAP/SMTP docs](https://senders.yahooinc.com/developer/documentation/))
- Mail scopes (once approved on the YDN app): `mail-r` (read), `mail-w` (write); also `email`, `profile`, contacts/calendar scopes. Example OpenID scope string: `openid mail-r`. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/); [OpenID Getting Started](https://developer.yahoo.com/oauth2/guide/openid_connect/getting_started.html))
- Yahoo and AOL share identity infrastructure; **separate client credentials per namespace**. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- For third-party apps that **do not** use Yahoo branded sign-in, Yahoo Help documents **app passwords** (generate under Account Security → External connections). App passwords remain valid after main password change until deleted. ([Yahoo Help — App passwords](https://help.yahoo.com/kb/new-mail-for-desktop/generate-manage-rd-party-passwords-sln15241.html); [IMAP settings](https://help.yahoo.com/kb/SLN4075.html))

### 3.2 APIs / protocols

- Official position: Yahoo **no longer supports proprietary Mail APIs**; third parties use **IMAP, CardDAV, CalDAV with OAuth2**, subject to policy. ([Developer Access](https://senders.yahooinc.com/developer/developer-access/))
- Servers: IMAP `imap.mail.yahoo.com:993` SSL; SMTP `smtp.mail.yahoo.com:465` or `587` SSL + auth. ([Yahoo Help IMAP](https://help.yahoo.com/kb/SLN4075.html); [Sender Hub](https://senders.yahooinc.com/developer/documentation/))
- IMAP/SMTP auth: SASL **OAUTHBEARER** (and XOAUTH2 where advertised). Clients should send IMAP **ID** with partner name assigned during approval. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- Folder model: IMAP SPECIAL-USE (`\All`, `\Archive`, `\Drafts`, `\Sent`, `\Junk`, `\Trash`, Inbox). OBJECTID for stable mailbox/message/thread IDs; MOVE supported. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))

### 3.3 Push / sync

- **IMAP IDLE** for near-real-time updates; due to server limits, IDLE reports **new messages and updates**, not deletes/EXPUNGE — clients must relist or use All Mail + CONDSTORE/QRESYNC. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- **MESSAGELIMIT** (example capability `MESSAGELIMIT=1000`): default Limited mode only exposes a partial folder; enable **UIDONLY** and use PARTIAL to walk full mailboxes. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- Experimental **All Mail** + CONDSTORE/QRESYNC for whole-mailbox incremental sync. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))

### 3.4 Quotas / rate limits

- Yahoo reserves the right to **impose rate limiting** and revoke API access. ([Developer Access policy](https://senders.yahooinc.com/developer/developer-access/))
- SMTP SIZE example in docs: ~36,700,160 bytes (~35 MB). ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- **Uncertainty:** No public per-user daily send quota table analogous to Gmail’s Help articles was found on Yahoo Help / Sender Hub during this research (see §5).

### 3.5 Review / verification

- Mail scopes are **not available for self-serve** setup in the developer console. Third parties must **apply** for commercial IMAP/CalDAV/CardDAV access and show compliance with Yahoo’s security/privacy policy. Contact: `mail-api@yahooinc.com`. ([Developer Access](https://senders.yahooinc.com/developer/developer-access/))
- Policy highlights: honest app description; use APIs only to serve Yahoo customers directly (no reselling API access); data only for relevant user-facing email/calendar/contact features; no selling/transfer for ads, profiling, monetization, engagement tracking; accessible privacy policy; demonstrate minimum security; Yahoo may revoke access. ([Developer Access](https://senders.yahooinc.com/developer/developer-access/))

### 3.6 Account-model differences (Yahoo)

- Consumer Yahoo Mail vs AOL: same OAuth/IMAP mechanisms, **different OAuth client credentials**. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- No Gmail-style label many-to-many; classic IMAP folders + SPECIAL-USE + optional All Mail. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- App-password path vs OAuth path: Help still documents app passwords for clients without Yahoo branded sign-in; OAuth mail scopes require prior Yahoo approval. ([App passwords](https://help.yahoo.com/kb/new-mail-for-desktop/generate-manage-rd-party-passwords-sln15241.html); [Developer Access](https://senders.yahooinc.com/developer/developer-access/))

---

## 4. Apple-platform constraints (directly needed)

- **ASWebAuthenticationSession**: authenticate via system-presented browser session (embedded secure browser on iOS; default browser / Safari on macOS); callback URL returned only to the calling app’s session. ([ASWebAuthenticationSession](https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession))
- Fits Google’s installed-app guidance (system browser, local/custom redirect) and Yahoo’s browser redirect / `oob` patterns. ([Google native OAuth](https://developers.google.com/identity/protocols/oauth2/native-app); [Yahoo OpenID Getting Started](https://developer.yahoo.com/oauth2/guide/openid_connect/getting_started.html))
- Broader App Store / MailKit / background networking constraints are deferred to ticket `03-research-apple-platform-constraints` — only auth session mechanics are cited here as directly required for provider OAuth.

---

## 5. Uncertainties (explicit)

1. **CASA for pure on-device Gmail clients:** Official pages say security assessment is required if restricted data is **stored or transmitted on servers**, and that apps accessing restricted data **from/through a third-party server** need annual assessment. ([Restricted scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)) Workspace policy still requires CASA practices for restricted scopes generally. ([Workspace policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy)) Whether a **Pub/Sub push relay that only forwards historyIds** (no message bodies) counts as “transmitting restricted scope data” should be confirmed with Google Trust & Safety during verification — treat as high risk until confirmed.
2. **Yahoo native-app client_secret:** Public Yahoo OAuth docs emphasize `client_secret` on token exchange; whether approved mail partners may use public-client / PKCE-only flows for iOS/macOS is not clearly stated on the fetched pages.
3. **Yahoo numeric quotas:** No first-party public daily send / concurrent connection tables found comparable to Gmail’s.
4. **Yahoo approval SLA / rejection criteria:** Policy text exists; timeline and acceptance rate for a new Apple MUA are not published.
5. **AOL as v1:** Same stack as Yahoo Mail OAuth/IMAP, but separate credentials — product may or may not include AOL in “Yahoo” v1.
6. **Agent Limited Use boundary:** Google FAQ allows personalized on-device models for user-facing features and forbids foundational-model training / unrestricted transfers. How Google reviewers treat **user-mediated remote agent sessions** that receive granted snippets is not spelled out; expect strict disclosure and consent requirements. ([OAuth FAQ](https://support.google.com/cloud/answer/13463817); [Workspace policy](https://developers.google.com/workspace/workspace-api-user-data-developer-policy))

---

## 6. Product implications for MailGant v1

### 6.1 Provider strategy

1. **Gmail:** Ship as **Gmail API client** with scopes justified to minimum set for the locked human baseline (likely `gmail.modify` or `gmail.readonly` + `gmail.compose` / send path — all restricted except pure `gmail.send`). Do **not** plan IMAP as the primary Gmail path for App Store launch.
2. **Yahoo:** Plan **IMAP/SMTP OAuth** only; start **Yahoo commercial access application early** — it is a launch blocker, not a polish task.
3. **Unified mailbox model** must abstract Gmail labels vs Yahoo folders (ticket `05-define-canonical-mailbox-model`).

### 6.2 Sync / notifications

- **Device-first ideal vs Gmail push:** Pure on-device cache sync can use history polling + optional background refresh. True low-latency Gmail push needs Pub/Sub → either accept a minimal relay cloud (and likely CASA) or accept polling latency on iOS/macOS.
- **Yahoo:** Prefer IMAP IDLE when foregrounded; background sync will be Apple-platform limited (see ticket 03); implement CONDSTORE/UIDONLY/PARTIAL correctly or large mailboxes break.

### 6.3 Security / verification schedule

- Budget calendar time for Google restricted verification (~weeks) + possible CASA if any server sees restricted data.
- Keep **mailbox content, search index, and tokens on-device** to maximize chance of avoiding CASA and to align with Yahoo/Google transfer bans.
- External **remote agents** must not become a silent redistribution of Yahoo/Google mailbox data; prefer local agents + explicit mediated sessions with disclosed consent (map Notes).

### 6.4 Multi-account

- Support consumer Gmail + Workspace with UX for “admin blocked this app.”
- Yahoo + optional AOL as separate OAuth apps/credentials.
- Respect Gmail’s 15-client IMAP connection limit if any IMAP fallback remains; Gmail API still subject to per-user quota units.

### 6.5 Concrete v1 constraints checklist

| # | Constraint |
| --- | --- |
| G1 | OAuth only for Gmail (no password collection). |
| G2 | Prefer Gmail API; avoid `https://mail.google.com/` unless permanent delete bypassing trash is a hard requirement. |
| G3 | Restricted-scope verification before >100 users. |
| G4 | Encrypt OAuth tokens at rest (Keychain); Limited Use disclosure in product + privacy policy. |
| G5 | Implement history sync + full-resync on 404; do not rely solely on Pub/Sub. |
| G6 | Honor 6,000 units/user/min and sending caps (500 consumer / 2,000 Workspace). |
| Y1 | Obtain Yahoo mail OAuth approval before promising Yahoo in App Store listing. |
| Y2 | Implement OAUTHBEARER IMAP/SMTP + IMAP ID partner string. |
| Y3 | Handle MESSAGELIMIT / UIDONLY / PARTIAL; IDLE without delete events. |
| Y4 | Do not depend on a Yahoo proprietary REST Mail API. |
| A1 | Use ASWebAuthenticationSession (or Google Sign-In SDK) for OAuth on Apple platforms. |
| X1 | Do not put mailbox bodies in MailGant cloud for v1 if avoiding CASA / Yahoo transfer bans is a goal. |

---

## 7. Source index

| Source | URL | Accessed |
| --- | --- | --- |
| Gmail API scopes | https://developers.google.com/workspace/gmail/api/auth/scopes | 2026-08-15 |
| Gmail API quotas | https://developers.google.com/workspace/gmail/api/reference/quota | 2026-08-15 |
| Gmail push | https://developers.google.com/workspace/gmail/api/guides/push | 2026-08-15 |
| Gmail sync | https://developers.google.com/workspace/gmail/api/guides/sync | 2026-08-15 |
| Gmail labels | https://developers.google.com/workspace/gmail/api/guides/labels | 2026-08-15 |
| Gmail XOAUTH2 | https://developers.google.com/gmail/imap/xoauth2-protocol | 2026-08-15 |
| Gmail handle errors | https://developers.google.com/workspace/gmail/api/guides/handle-errors | 2026-08-15 |
| OAuth iOS/Desktop | https://developers.google.com/identity/protocols/oauth2/native-app | 2026-08-15 |
| Restricted scope verification | https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification | 2026-08-15 |
| Workspace OAuth considerations | https://developers.google.com/identity/protocols/oauth2/production-readiness/google-workspace | 2026-08-15 |
| Workspace user data policy | https://developers.google.com/workspace/workspace-api-user-data-developer-policy | 2026-08-15 |
| Workspace auth overview | https://developers.google.com/workspace/guides/auth-overview | 2026-08-15 |
| OAuth verification FAQ | https://support.google.com/cloud/answer/13463817 | 2026-08-15 |
| Verification requirements | https://support.google.com/cloud/answer/13464321 | 2026-08-15 |
| Restricted scopes list | https://support.google.com/cloud/answer/13464325 | 2026-08-15 |
| Gmail add to client / IMAP | https://support.google.com/mail/answer/7126229 | 2026-08-15 |
| Gmail send/get limits | https://support.google.com/mail/answer/22839 | 2026-08-15 |
| Gmail bounced / 500/day | https://support.google.com/mail/answer/6596 | 2026-08-15 |
| Workspace sending limits | https://support.google.com/a/answer/166852 | 2026-08-15 |
| Yahoo OAuth 2.0 Guide | https://developer.yahoo.com/oauth2/guide/ | 2026-08-15 |
| Yahoo OpenID Getting Started | https://developer.yahoo.com/oauth2/guide/openid_connect/getting_started.html | 2026-08-15 |
| Yahoo Sender Hub IMAP/SMTP | https://senders.yahooinc.com/developer/documentation/ | 2026-08-15 |
| Yahoo Developer Access / policy | https://senders.yahooinc.com/developer/developer-access/ | 2026-08-15 |
| Yahoo Help IMAP settings | https://help.yahoo.com/kb/SLN4075.html | 2026-08-15 |
| Yahoo Help app passwords | https://help.yahoo.com/kb/new-mail-for-desktop/generate-manage-rd-party-passwords-sln15241.html | 2026-08-15 |
| ASWebAuthenticationSession | https://developer.apple.com/documentation/authenticationservices/aswebauthenticationsession | 2026-08-15 |

**Protocols referenced (standards):** IMAP4rev1 (RFC 3501), SASL (RFC 4422), SMTP AUTH (RFC 4954), SASL-IR (RFC 4959), OAUTHBEARER (RFC 7628), OAuth 2.0 / PKCE (RFC 6749 / 7636) — as cited by Google/Yahoo developer docs above.
