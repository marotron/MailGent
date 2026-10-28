# MailGent Privacy Policy

**Last updated:** 28 October 2026

**This 0.21.0 alpha binary does not match every v1 behavior below.** It reads Apple Mail on disk (`~/Library/Mail`) when that folder is readable (Full Disk Access, or a folder you choose). Pairing credentials are a local JSON file under Application Support (`pairing.json`), not Keychain — multiple machine-local agents (e.g. Cursor and Grok Bot) may each hold a distinct Bearer. When you enable **outbound leak guard** and opt in placements, MailGent scans message subject and body on your Mac before disclosing them to a paired agent — redacting or withholding matches per your Grant Desk rules; originals stay in the local access log, not in MCP responses. Leak-guard policy is shared across agents. **Rules** (Pass / Block, optional When windows) are shared definitions; enabling a rule on a placement is per agent and can conditionally add or subtract fields on already-allowed messages. Grant fields may be set to **Ask**; when conditional access prompts are allowed in Settings, MailGent shows an on-device Allow / Block window for each request before disclosing those fields to the agent. From that window you can optionally pick Subject / From into a Pass/Block rule and edit it in the right pane (including Enable on: this mailbox or this account · all mailboxes); Allow or Block writes the shared rule file (when armed) and enables it for the prompting agent on the chosen target. Closing the window blocks this read without writing a rule. Allow, Block, or closing a window decides only that request. When an armed rule is written, other open Ask windows for the same agent are checked against that rule and may re-run grant→rules→Ask (including a new prompt for leftover Ask fields only); unmatched windows stay open. When **Remember Ask decisions** is on in Settings, MailGent reuses those Allow / Block answers per field for the same message for a validity window you choose (15 minutes, 1 hour, 24 hours, 30 days, 1 year, forever, or until MailGent quits; this agent only by default, or all paired agents if you choose). Timed and forever answers are stored in Application Support as `ask-decisions.json` and reload after relaunch; until MailGent quits stays in memory only. Forgetting an agent clears that agent’s entries from memory and the file. This is not a standing grant. When a grant allows Attachment Content and an agent calls `get_attachment`, MailGent writes a copy of that attachment to the macOS temporary folder (`MailGent-agent-attachments`) so the agent can read it; MailGent does not delete these copies itself (macOS clears the temporary folder over time). MCP `list_accounts` returns Mail account display names and email addresses only for accounts with at least one grant-filtered placement by default; turn on Settings → **Reveal accounts with no placements** to also disclose identities with empty `placements` (ungranted mailbox names are still not listed). When **Allow agents to propose sending mail** is on in Settings, a paired agent may call MCP `propose_send`; MailGent shows an on-device confirm dialog (Send / Open in Mail / Cancel) and only then may use Automation (Apple Events) to compose or send that plain message in Apple Mail — MailGent does not speak SMTP. If a `sender` is requested, MailGent resolves it against Mail’s live account emails (treating Gmail/Googlemail local-part dots as the same mailbox) and aborts when From would not stick (no silent send from another account). Closing the dialog cancels without sending. When Settings → Experimental → **Propose-send context thread** is also on, `propose_send` may include a `context` timeline; you choose a **Personal vault root** folder and MailGent stores a security-scoped bookmark for it locally (UserDefaults). MailGent then reads mail already in its index and vault files under that root only to render the on-device confirm rail for you — it does not upload vault contents, and agents still only receive the usual MCP tool responses they already requested. On first launch MailGent pairs Cursor and, if `~/.cursor/mcp.json` exists, adds a `mailgent` entry with Cursor's Bearer; new agents have no grants until you add them. The access log cannot be changed by agents; you can delete all entries, or entries older than 24 hours, in Settings (no Touch ID step in this build). Gmail/Yahoo OAuth, Keychain tokens, broader mutation approvals, and remote sessions in this policy are planned v1, not this build.

This policy describes how MailGent (“MailGent,” “we,” “us”) handles information when you use the MailGent macOS application and related local services.

MailGent is an early-stage product. This document reflects the intended v1 design. If a shipped build behaves differently, that build’s in-app disclosures control until this policy is updated.

**Contact:** marotron@gmail.com

---

## 1. What MailGent is

MailGent is a **macOS companion** used alongside Apple Mail. It is **not** a replacement daily email client.

MailGent helps you:

- Connect personal mail accounts (planned v1 providers: Gmail and Yahoo)
- Search and review mail locally
- Inspect and edit drafts
- Approve or deny agent-proposed mail mutations (such as send, move, trash, or permanent delete)
- Manage per-agent access policies and a local audit log
- Open source messages in Apple Mail

MailGent also lets you grant **scoped, revocable** access to **external AI agents** that you choose to pair. MailGent does not ship a built-in AI assistant in v1.

---

## 2. Information we process

### 2.1 Account and authentication data

When you connect a mail provider (for example Yahoo or Google), MailGent uses that provider’s OAuth (or equivalent) sign-in flow.

We may store on your device:

- Account identifiers needed to operate the connection (such as email address and provider account id)
- OAuth access and refresh tokens
- Connection / sync health metadata

**Tokens are stored in the macOS Keychain** (or equivalent OS-secure storage), not in plain text in the app bundle.

### 2.2 Mailbox content

To provide search, read, draft review, approvals, and sync, MailGent may store on your Mac:

- Message metadata (headers, folder/label placement, dates, flags)
- Message bodies and attachments needed for local features
- A local search index
- Drafts you or an agent create in MailGent
- Pending mutation proposals and approval decisions

### 2.3 Agent, policy, and audit data

MailGent stores on your device:

- Agent identities and pairing / session state
- Grants, scopes, capabilities, and deny rules you configure
- An append-only local audit log of agent access and related security events
- Optional local notification preferences

### 2.4 App preferences

Non-sensitive UI preferences may sync via mechanisms you enable (for example iCloud preference sync). MailGent’s v1 product intent is that **mailbox content, search index, credentials, and policy enforcement stay on-device**.

---

## 3. How we use information

We use the information above only to:

1. Provide MailGent’s user-facing companion features
2. Enforce the access policies and approvals you configure
3. Maintain local security, sync health, and auditability
4. Improve reliability of the app on your device

We do **not** use mailbox content for:

- Advertising or ad targeting
- Building marketing profiles
- Selling or brokering personal data
- Training foundational / general-purpose AI models on your mail

---

## 4. Device-first posture (no mailbox-reading cloud)

MailGent’s v1 design is **device-first**:

- Mailbox cache, search index, credentials, and policy enforcement stay on your Mac
- MailGent does **not** operate a cloud service whose purpose is to read your mailbox content
- Local agents connect on-device under your grants
- Remote agents require **explicit, user-mediated, expiring sessions** — there is no unattended public inbox endpoint that redistributes your mail

If a future feature needs a cloud component, we will update this policy before enabling it and obtain any additional consent required.

---

## 5. Sharing with third parties

### 5.1 Mail providers

When you connect Yahoo, Google, or another provider, that provider processes your account under **their** privacy policy and terms. MailGent only accesses what you authorize through OAuth scopes.

### 5.2 AI agents you pair

Mail content may be disclosed to an external agent **only when you**:

- Pair / connect that agent
- Grant it scopes and capabilities
- (For mutations such as send, trash, permanent delete, move, and similar) approve the action in MailGent

Agents are deny-by-default. You can revoke, suspend, or forget an agent. By default, `list_accounts` does not disclose identities without a read grant. If you enable **Reveal accounts with no placements**, a paired agent may learn display names and email addresses for those empty-placement accounts (no message body or mailbox inventory is disclosed that way).

**Important:** Once mail content is sent to an agent you chose, that agent’s own privacy practices apply to what it receives. Choose agents carefully.

### 5.3 No sale of mail data

We do not sell your mailbox content. We do not share it with advertisers or data brokers.

### 5.4 Legal requests

If we ever operate infrastructure that holds non-mail operational data and are legally compelled to disclose it, we will do so only as required by law. v1 mailbox content is intended to remain on your device under your control.

---

## 6. Retention

- Local mailbox cache, index, tokens, policies, and audit logs remain on your Mac until you delete them, disconnect the account, revoke the agent, or uninstall / reset MailGent
- Manual purge of audit data (when offered) may require local authentication (for example Touch ID), consistent with the product’s security design
- Provider tokens remain until you disconnect the account or the provider revokes them

---

## 7. Your choices and controls

You can:

- Connect or disconnect mail accounts
- Revoke OAuth access at the provider (Yahoo Account / Google Account security settings)
- Pair, suspend, revoke, or forget agents
- Tighten or remove agent grants
- Approve or deny mutation proposals
- Delete local MailGent data by removing local app data / uninstalling (exact steps depend on the shipped build)

---

## 8. Children

MailGent is not directed at children under 16 (or the minimum age required in your jurisdiction). Do not use MailGent with children’s mail accounts.

---

## 9. International users / GDPR / CCPA readiness

MailGent is designed so that mailbox content and credentials stay on your device, and so that agent access and mutations require your explicit control.

Before broad public distribution, we intend to:

- Keep this privacy policy accurate and accessible
- Align consent and disclosures with applicable laws (including GDPR and CCPA/CPRA where they apply)
- Complete any formal legal review needed for the jurisdictions we ship into

This section is a product commitment for launch readiness, not a claim that counsel has already signed off.

---

## 10. Security

We design MailGent to:

- Store credentials in OS-secure storage (Keychain)
- Fail closed when policy or session checks cannot be completed safely
- Keep a local audit trail of agent access
- Avoid operating a mailbox-content cloud in v1

No method of electronic storage is perfectly secure. Protect your Mac login and any paired agents.

---

## 11. Changes

We may update this policy as the product evolves. The “Last updated” date will change when we do. Material changes that expand cloud processing or third-party sharing of mailbox content will be called out clearly before those features ship.

---

## 12. Contact

Questions about privacy: marotron@gmail.com

Project repository: the public GitHub repository where this `PRIVACY.md` is published.
