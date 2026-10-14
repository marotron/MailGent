# Handoff: Ask-allowed Attachment content does not unlock `get_attachment`

**Status:** fixed on `fix/get-attachment-ask-resolution` (tests green; PATCH 0.11.4 when landing)  
**Repo:** `/Users/marotron/dev/MailGent`  
**Reported from:** Personal vault session (SJIB Gold Card search) · Cursor agent on `user-mailgent` MCP  
**App version in use:** ~0.11.2 alpha (INDEX)  
**Suggested branch:** `fix/get-attachment-ask-resolution`  
**Suggested version:** PATCH (bug) once fix lands — follow `.cursor/rules/versioning.mdc`

---

## Goal

Make MCP `get_attachment` honour the same grant field resolution as `get`, especially when **Attachment content** is in **Ask** mode and the user already Allowed it on the Ask prompt.

Until fixed, agents can list attachment names after Ask Allow, then fail to fetch bytes with a note that looks like a base-grant misconfiguration.

---

## User / agent scenario (live)

**Intent:** Find SJIB / ECS Electrician Gold Card registration number from 2020 mail.

**Mailbox:** `markujawa@gmail.com`  
**Account ID:** `2D1F6879-5270-4EB9-87A0-5A3D74ECFDCB`  
**Target message:** Sent Mail id **`5067`**  
**Placement:** `[Google Mail]/Sent Mail`  
**Date:** Mon, 16 Nov 2020 15:43:10 +0000  
**Subject:** `SJIB Grade (ECS) Card Renewal`  
**To:** `Grading <grading@sjib.org.uk>`  
**internetMessageID:** `<EAB36CE0-1EBC-4945-9CE3-55CC207595ED@gmail.com>`

**Attachments on that message (names + sizes from `get`):**

| filename | byteCount |
|----------|-----------|
| `Renewal Application 2020 comple flt_16112020.pdf` | 416376 |
| `2020.Marek_Kujawa_1382_sqr.jpeg` | 460879 |
| `2020.C&G2382- 18th.pdf` | 784951 |

(Registration number is expected inside the renewal-form PDF; not present in body text.)

---

## Repro (MCP)

1. Pair Cursor → `user-mailgent` (loopback).
2. Grant for this Gmail account: Body / Attachment names / Attachment content in **Ask** (or otherwise such that `get` triggers Ask and user Allows those fields).
3. `get` with account / placement / id `5067`.
4. Observe response includes attachments list.
5. `get_attachment` with same ids + filename `Renewal Application 2020 comple flt_16112020.pdf`.

### Actual `get` (2026-10-14 ~21:02 Europe/Warsaw) — abbreviated

```json
{
  "id": "5067",
  "subjectAccess": "granted",
  "subjectAccessReason": "grant",
  "bodyAccess": "sanitized",
  "bodyAccessReason": "leak_guard",
  "sanitizedRules": ["Phone numbers"],
  "attachmentAccess": "granted",
  "attachments": [
    { "filename": "Renewal Application 2020 comple flt_16112020.pdf", "byteCount": 416376 },
    { "filename": "2020.Marek_Kujawa_1382_sqr.jpeg", "byteCount": 460879 },
    { "filename": "2020.C&G2382- 18th.pdf", "byteCount": 784951 }
  ],
  "conditionalAccessFields": ["Body", "Attachment names", "Attachment content"],
  "isPartial": true
}
```

Access Log label for `conditionalAccessFields` is **"Ask user allowed"** (`AccessLogView.swift`). So the human Allowed Attachment content on the Ask for this `get`.

### Actual `get_attachment` — same message, same session

```json
{
  "accountID": "2D1F6879-5270-4EB9-87A0-5A3D74ECFDCB",
  "placement": "[Google Mail]/Sent Mail",
  "id": "5067",
  "filename": "Renewal Application 2020 comple flt_16112020.pdf",
  "byteCount": 416376,
  "isPartial": true,
  "attachmentContentAccess": "not_granted",
  "note": "Attachment content omitted: the active grant does not allow attachment content. Ask the user to enable Attachment Content on the grant."
}
```

Same `not_granted` for `2020.C&G2382- 18th.pdf`.

---

## Root cause (source)

| Call path | Grant resolution |
|-----------|------------------|
| `get` | `effectiveGrant` → **`resolveConditionalFields`** (Ask prompt) → applies confirmed bits including `attachmentContent` for that response |
| `getAttachment` | `effectiveGrant` **only** → checks `grant.fields.attachmentContent` with **no Ask resolution** |

Evidence:

```630:688:MailStore/Sources/AgentReadAPI.swift
    public func getAttachment(
        ...
            guard let grant = effectiveGrant(for: probe, agentID: agent.id) else {
                ...
            }
            let fields = grant.fields
            ...
            if !fields.attachmentContent {
                result = AttachmentAccessResult(
                    ...
                    attachmentContentAccess: .notGranted,
                    note: "Attachment content omitted: the active grant does not allow attachment content. Ask the user to enable Attachment Content on the grant."
                )
```

Contrast `get`, which awaits `resolveConditionalFields` before field masks / audit `conditionalAccessFields`.

So when Attachment content mode is **Ask**:

1. User Allows on `get` → MCP returns `conditionalAccessFields` including `"Attachment content"` and `attachmentAccess: granted` (names).
2. Agent correctly calls `get_attachment`.
3. `get_attachment` re-reads base grant; Ask bit is still not On → `not_granted`.
4. Note tells the user to "enable Attachment Content on the grant" — misleading if they already Allowed it on Ask, or if they only want Ask-not-always-On.

`attachmentAccess` on `get` means **attachment metadata / names** (`attachmentMetadataGranted`), not bytes. Content uses a separate field. That split is fine; the bug is Ask confirmation not applying to `get_attachment`.

---

## Why this matters for agents

- Agents follow tool docs: "When attachments are listed and content is granted, use `get_attachment`."
- After Ask Allow, `conditionalAccessFields` literally lists `"Attachment content"`, so agents (and users) believe content is unlocked.
- Failure mode looks like a user config mistake; wasted wall-clock on vault/profile updates and disk search fallbacks.
- Related user work blocked: file SJIB renewal PDF + C&G 2382 into `Personal/02-jobs/00-profile/evidence/`.

Prior related handoff (different bug — ENDS From matcher):  
`Personal/01-house/00-past/01-B138RJ/03-OVO/HANDOFF-2026-09-30-mailgent-body-grant.md` (body Pass rules). This report is **Ask + get_attachment**, not ENDS matching.

---

## Suggested fix directions (pick one; do not invent scope creep)

### A. Preferred: resolve Ask on `get_attachment` too

Mirror `get`: call `resolveConditionalFields` (or a narrower Ask for Attachment content only) before the `fields.attachmentContent` check.

Pros: consistent with Body Ask; one Allow can unlock bytes.  
Cons: may show a second Ask unless decisions are cached (see B).

### B. Preferred UX: cache Ask Allow for content on the same message

After `get` Ask Allow includes Attachment content, remember for this agent + message (short TTL or until ingest) so immediately following `get_attachment` calls succeed without a second popup.

Pros: matches agent workflow (get → get_attachment).  
Cons: needs a small session cache; define revoke / Block behaviour.

### C. Docs / MCP note only (insufficient alone)

If product insists Attachment content Ask only applies when base C is On: update MCP tool description + `get` note when names are granted but content remains Ask-denied for `get_attachment`. Still leave agents stuck until user turns C On permanently.

### D. Do not “fix” by enabling C on all Gmail Scope

Wider privacy surface; not required if Ask works end-to-end.

---

## Tests to add

1. Grant: Attachment content = **Ask**. Prompter Allows. `get` → `conditionalAccessFields` contains `"Attachment content"`. Immediate `getAttachment` → `attachmentContentAccess == .granted` (and temp path present).
2. Same, but prompter **Blocks** content → `get_attachment` → `.notGranted` (and ideally `conditionalBlockedFields` / clear note).
3. Attachment content = **Off** (not Ask) → `get_attachment` → `.notGranted` with existing note.
4. Attachment content = **On** → unchanged happy path (existing LoopbackMCPServerTests / AgentReadAPITests).
5. Optional: second `get_attachment` for another filename on same message after one Allow (both granted).

Existing nearby tests: `MailStore/Tests/AgentReadAPITests.swift`, `LoopbackMCPServerTests.swift` (`attachmentContentAccess`).

---

## Quick verify after fix

```text
get id 5067 → attachmentAccess=granted, conditionalAccessFields includes "Attachment content"
get_attachment filename "Renewal Application 2020 comple flt_16112020.pdf"
  → attachmentContentAccess=granted
  → path points to readable PDF (~416 KB)
```

Optional product follow-up (not blocking): when `isPartial: true` and content granted, confirm Apple Mail has fully downloaded the part (`not_available` path already exists).

---

## Out of scope / do not regress

- Leak guard phone sanitization on body (`bodyAccess: sanitized`, `leak_guard`) — working as designed in this capture.
- Search/list remaining header-only.
- OVO ENDS `@domain` Pass-rule From matching (separate, already documented).
- Enabling Attachment Content globally on Gmail as the only workaround narrative in agent-facing copy after fix.

---

## Workaround for humans today (until PATCH)

1. MailGent → Grant desk → Cursor (or active agent) → enable **Attachment Content** as **On** (not only Ask) for the Gmail scope used by `2D1F6879-…`, **or**
2. Open message in Apple Mail and save the PDFs manually into the vault.

Then re-run `get_attachment`.

---

## Context links (vault, not MailGent repo)

- Thread notes: `Personal/02-jobs/00-profile/evidence/INFO.md` (SJIB section)
- Profile quals: `Personal/02-jobs/00-profile/profile.md` (SJIB Gold Card still missing number/expiry)
- Session log: `Personal/02-jobs/LOG.md` · 2026-10-14 (~20:44 Europe/Warsaw)
- Chat transcript: Cursor agent `93fa8f3a-cf97-4da3-b2f6-55c24dee0af5`
