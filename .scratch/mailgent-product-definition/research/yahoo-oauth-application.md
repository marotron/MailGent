# Research: Yahoo commercial IMAP/SMTP OAuth application process

**Question:** From first-party Yahoo sources only, what is the current commercial / Sender Hub application process for IMAP/SMTP OAuth mail scopes (`mail-r` / `mail-w`), and what material facts were missing or under-specified in prior research?

**Access date for all citations unless noted:** 2026-08-16  
**Prior research:** [`gmail-yahoo-integration.md`](./gmail-yahoo-integration.md) (2026-08-15)  
**Out of scope:** Third-party blog/Stack Overflow how-tos; actually submitting an application; modifying ticket 15 or the feature map

---

## 1. Decision-oriented summary

| Topic | Source-backed finding | vs prior note |
| --- | --- | --- |
| Submission channel | Dedicated Sender Hub form + questions email | **Material add:** exact form URL and field inventory were missing |
| Required info | Company/person, app, privacy, data-use, compliance, volume, API type, YDN email, contract/security flags | **Material add** |
| Partner name | IMAP `ID` `NAME` = partner name/ID **assigned during approval**; not a form field | Confirmed; sequencing clarified |
| Credentials timing | YDN account (and thus app/credential management) required **on the form**; mail scopes listed on YDN profile **once approved** | **Material add** |
| Yahoo vs AOL | One form covers AOL + Yahoo customers; same OAuth mechanism; **separate client credentials per namespace** | Confirmed; form scope clarified |
| SLA / status | No published review SLA or status portal; security-audit results “might expedite” | Still unpublished; form adds only expedite hint |
| Submit without company/user details? | **No** — required fields include Name, Company Name, contact email, YDN account email, product URL, privacy-policy URL | New feasibility answer |

**Verdict for ticket 15:** Application **cannot** be truthfully completed without real applicant/company identity, product + privacy URLs on the **same domain**, a YDN account email, and substantive answers on data collection/use/sharing and expected Yahoo users / API call volume. Placeholder or anonymous submission would violate Yahoo’s honesty/accuracy policy and fail required form fields.

---

## 2. Submission channel

1. Mail scopes are **not** available via self-serve developer-console setup. Third parties must apply and show policy compliance. ([Developer Access](https://senders.yahooinc.com/developer/developer-access/))
2. Commercial access to **IMAP, CalDAV, and CardDAV** is requested by filling out the Sender Hub form: [developer-access-mail-form](https://senders.yahooinc.com/developer/developer-access-mail-form/). Questions: `mail-api@yahooinc.com`. ([Developer Access](https://senders.yahooinc.com/developer/developer-access/))
3. Form title/intro: “Yahoo Mail API Access” — apps/services may offer **AOL and Yahoo** customers Mail, Contacts, and Calendar via IMAP, CardDAV, and CalDAV. ([Mail access form](https://senders.yahooinc.com/developer/developer-access-mail-form/))
4. IMAP/SMTP OAuth docs link the same access request path for starting review/approval when mail scope is not already approved. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))

**Not found on first-party pages:** a separate SMTP-only application path, a public ticket/status dashboard for mail-API applications, or a stated review SLA (days/weeks).

---

## 3. Required business / app / privacy / security information

All of the following form fields are marked **Required** on the live form (accessed 2026-08-16):

| Field | Notes on form |
| --- | --- |
| Email Address / Re-enter Email Address | Contact email |
| Name | Requester identity |
| Company Name | Business identity |
| Name of your application / service | App identity |
| URL to application / service | “domain of this URL needs to match the domain of your privacy URL” |
| Description of your application / service | Specific use cases for Yahoo APIs |
| Data collection and processing | How Yahoo user data is used; whether scanning/extracting mail, contacts, or calendar |
| Data use | Advertising segments / monetization / other uses |
| Data sharing | Any 3rd-party sharing: what, why, whom |
| Compliance with Laws | Yes / No / Other — GDPR consent; CCPA readiness |
| Users / API calls | Expected Yahoo user count and API calls per hour |
| API required | Checkboxes: **IMAP**, **CardDav**, **CalDav** (SMTP not a separate checkbox) |
| Your YDN account | Email for Yahoo Developer Network account; “You need a YDN account to manage your API access” (links `https://developer.yahoo.com/mail/`) |
| Existing contract | Yes/No — existing contract with any Yahoo property (e.g. Yahoo, AOL) |
| 3rd party security audit | Yes/No — sharing results “might expedite your application” |
| Privacy Policy | URL; domain must match product URL |

Sources: [Mail access form](https://senders.yahooinc.com/developer/developer-access-mail-form/).

Policy expectations that the narrative answers must satisfy (not separate form widgets): honest/accurate identity and use description; APIs only to serve Yahoo customers directly (no reselling API access); data only for relevant user-facing email/calendar/contact features; no transfer/sale for ads, profiling, monetization, or engagement tracking; accessible privacy disclosures + per-use-case consent; demonstrate minimum security; agree to [Yahoo APIs Terms of Use](https://policies.yahoo.com/us/en/yahoo/terms/product-atos/apiforydn/index.htm); Yahoo may revoke/suspend access and impose rate limits. ([Developer Access — policy details](https://senders.yahooinc.com/developer/developer-access/))

Form consent: submissions subject to Yahoo’s privacy policy at [legal.yahoo.com](https://legal.yahoo.com/index.html). ([Mail access form](https://senders.yahooinc.com/developer/developer-access-mail-form/))

---

## 4. Partner-name requirement

- After approval, IMAP clients should send IMAP `ID` with **`NAME`** = “the partner name or the ID assigned during the approval process,” plus `VERSION`, `OS`, `OS-VERSION`. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- The access **form does not collect** a partner name. Expect Yahoo to assign it as part of approval, then use that string in IMAP `ID`.

---

## 5. Credential creation: before vs after approval

| Step | What first-party sources say |
| --- | --- |
| Create Yahoo account / YDN app | OpenID Connect getting started: create Yahoo account → [create application](https://developer.yahoo.com/apps/create/) → receive Client ID + Client Secret; optionally select API Permissions including Mail Read in the tutorial UI. ([OpenID Getting Started](https://developer.yahoo.com/oauth2/guide/openid_connect/getting_started.html); [OAuth 2.0 Guide — Before You Begin](https://developer.yahoo.com/oauth2/guide/)) |
| Apply for commercial mail access | Mail scopes **not** self-serve; use Sender Hub form; form **requires YDN account email**. ([Developer Access](https://senders.yahooinc.com/developer/developer-access/); [Mail access form](https://senders.yahooinc.com/developer/developer-access-mail-form/)) |
| After approval | “Supported mail, contacts and calendar scopes are also listed in your YDN application profile **once approved**.” Scopes include `mail-r`, `mail-w` (plus `email`, `profile`, contacts/calendar scopes). ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/)) |

**Working sequence implied by Yahoo’s own pages:**

1. Create YDN account/app credentials **before or as part of** applying (form requires the YDN account email).  
2. Submit Sender Hub form for commercial IMAP (and optionally CardDAV/CalDAV).  
3. After approval, mail scopes appear on the YDN app profile; use `mail-r` / `mail-w` in OAuth; use assigned partner name/ID in IMAP `ID`.

**Tension to treat carefully:** OpenID “Getting Started” still shows checking **Mail → Read** when creating an app, while Developer Access states those scopes are **not** available for self-serve setup. Prefer the Sender Hub commercial-access policy for MailGent planning; treat the tutorial Mail checkbox as incomplete relative to today’s restricted-scope process.

Apps/create and My Apps require Yahoo sign-in; unauthenticated scrapes only reach the login wall. ([developer.yahoo.com/apps/create/](https://developer.yahoo.com/apps/create/), accessed 2026-08-16)

---

## 6. Consumer Yahoo vs AOL requirements

- Form explicitly covers offering access to **AOL and Yahoo** customers. ([Mail access form](https://senders.yahooinc.com/developer/developer-access-mail-form/))
- Shared identity infrastructure / same OAuth token mechanism for Yahoo and AOL accounts; applications need a **separate set of client credentials for each namespace**. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- Docs present Yahoo vs AOL server-address and “API login Yahoo” / “API login AOL” tabs. Public scrape of the default (Yahoo) tab lists IMAP `imap.mail.yahoo.com`, SMTP `smtp.mail.yahoo.com`, and OpenID discovery at `https://api.login.yahoo.com/.well-known/openid-configuration`. AOL-tab hostnames were **not** present in the static HTML payload for the Yahoo tab. ([Sender Hub documentation](https://senders.yahooinc.com/developer/documentation/))
- Existing-contract question mentions Yahoo property examples including **Yahoo, AOL**. ([Mail access form](https://senders.yahooinc.com/developer/developer-access-mail-form/))

**Implication:** One commercial application can request IMAP for the Yahoo/AOL mail stack, but shipping AOL still needs **second OAuth client credentials** after approval. AOL-specific hostnames should be read from the AOL tab in Sender Hub docs (or Yahoo contact) before implementation — not assumed identical to Yahoo hosts.

---

## 7. Known SLA / status mechanics

| Mechanism | First-party status |
| --- | --- |
| Review timeline | **Not published** on Developer Access, form, or IMAP docs (reconfirmed 2026-08-16). |
| Status tracking | **No** public application-status UI described. Questions → `mail-api@yahooinc.com`. |
| Expedite signal | Completing / sharing a recent 3rd-party security assessment “might expedite your application.” ([Mail access form](https://senders.yahooinc.com/developer/developer-access-mail-form/)) |
| Post-approval enforcement | Yahoo may revoke/suspend for policy/ToS non-compliance; may impose rate limiting; may revoke API access at any time unless prohibited. ([Developer Access](https://senders.yahooinc.com/developer/developer-access/)) |
| Broader API ToS | Yahoo may change/suspend APIs; support is discretionary; security reviews possible with notice. ([APIs Terms of Use](https://policies.yahoo.com/us/en/yahoo/terms/product-atos/apiforydn/index.htm)) |

---

## 8. Can MailGent submit without user/company details?

**No.**

Minimum blockers from the required form alone:

- Personal **Name** + **Company Name** + contact **Email**
- **YDN account** email (implies a Yahoo developer identity already exists)
- Live **product URL** and **privacy-policy URL** on the **same domain**
- Detailed answers on data collection, use, sharing, legal compliance, and expected users/API volume
- Honesty/accuracy obligations in Yahoo’s developer access policy

Anonymous, fictional-company, or “TBD URL” submissions are incompatible with the published form and policy.

---

## 9. Source index

| Source | URL | Accessed |
| --- | --- | --- |
| Developer Access (process + policy) | https://senders.yahooinc.com/developer/developer-access/ | 2026-08-16 |
| Mail API access form | https://senders.yahooinc.com/developer/developer-access-mail-form/ | 2026-08-16 |
| IMAP/SMTP OAuth documentation | https://senders.yahooinc.com/developer/documentation/ | 2026-08-16 |
| Yahoo OAuth 2.0 Guide | https://developer.yahoo.com/oauth2/guide/ | 2026-08-16 |
| OpenID Connect Getting Started | https://developer.yahoo.com/oauth2/guide/openid_connect/getting_started.html | 2026-08-16 |
| OAuth 2.0 FAQ | https://developer.yahoo.com/oauth2/guide/faq/ | 2026-08-16 |
| Yahoo APIs Terms of Use | https://policies.yahoo.com/us/en/yahoo/terms/product-atos/apiforydn/index.htm | 2026-08-16 |
| Create Application (login-gated) | https://developer.yahoo.com/apps/create/ | 2026-08-16 |

**Still unknown from first-party public pages:** numeric review SLA; formal acceptance criteria beyond policy text; exact post-submit confirmation/email UX; whether the OpenID Create Application “Mail” checklist still enables any provisional mail scope without Sender Hub approval; AOL IMAP/SMTP hostnames from the AOL server-address tab (not in default-tab HTML).
