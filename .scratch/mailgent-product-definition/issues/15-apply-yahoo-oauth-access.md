# Apply for Yahoo Mail OAuth Developer Access

Type: task
Status: resolved

## Question

Complete Yahoo’s commercial developer / Sender Hub access application for IMAP/SMTP OAuth (`mail-r` / `mail-w`), record application status and any partner-name or client-credential requirements, and capture resulting facts later tickets need for Yahoo-backed v1 feasibility.

## Answer

**Submitted** 2026-08-17 via [Yahoo Mail API Access form](https://senders.yahooinc.com/developer/developer-access-mail-form/). Confirmation: “Your request has been submitted!”

| Fact | Value |
| --- | --- |
| Status | Submitted — awaiting Yahoo review (no published SLA / status portal) |
| YDN app | MailGent (public client; Client ID in local `.env`; no Client Secret) |
| YDN account | `you@yahoo.com` (placeholder) |
| Product URL | `https://github.com/marotron/MailGent` |
| Privacy URL | `https://github.com/marotron/MailGent/blob/main/PRIVACY.md` |
| API requested | IMAP only (not CardDAV/CalDAV) |
| Partner IMAP `ID` `NAME` | **TBD** — assigned at approval; not on the form |
| Mail scopes | `mail-r` / `mail-w` appear on YDN profile **after** approval |
| Follow-up | `mail-api@yahooinc.com` |

Process research: [../research/yahoo-oauth-application.md](../research/yahoo-oauth-application.md). Walkthrough: [../examples/guide-yahoo-oauth-setup.html](../examples/guide-yahoo-oauth-setup.html).

## Comments

- [Verify Yahoo OAuth application](d938f331-842d-42ca-9c8c-93dce86e6cc3) wrote the cited research note from Sender Hub / YDN pages (2026-08-16).
- HTML walkthrough + paste-ready answers: [../examples/guide-yahoo-oauth-setup.html](../examples/guide-yahoo-oauth-setup.html).
- User: form confirmation “Your request has been submitted!” (2026-08-17).
