# Companion Read UI Prototype Then Shell

Type: prototype
Status: claimed
Blocked by: 03

## Question

Which of three structurally different companion read layouts should first ship keep, and can that shell search/read fixture mail (and, manually, live Mail after FDA) without looking like Mail.app?

## Context

**Branches:** `proto/companion-read-ui` then `feat/04-companion-shell` off `train/local-read`.

Locked IA from product ticket 09: **control-first** default, not a Mail.app clone (Guideline 5.2.5). First-ship surfaces only: access health (FDA + last ingest), account/mailbox picker, search/read, open in Apple Mail if handoff works.

**Menu bar shell (locked):** MailGent has no Dock icon and no normal app window. Replace `WindowGroup` with `MenuBarExtra` + `Settings` scene; set `LSUIElement = YES` in the generated Info.plist (add to `project.yml` `INFOPLIST_KEY_*` settings). The companion UI opens as the `MenuBarExtra` popover or as a detached `Window` scene launched from it. The three layout variants must be prototyped inside this shell, not a standalone `WindowGroup`.

Prototype **sub-shape B**: a clearly named `PrototypeReadRoot` with **three structurally different** layouts and a floating variant switcher. Variants must differ in hierarchy (control-first vs search-first vs review desk), not color. Real fixture data behind all three.

**Stop and ask** which variant (or mix) to keep. Then implement only that on `feat/04-companion-shell`. Point this issue at the prototype branch; do not merge prototype chrome to `main`.

## Verify

A variant is picked; companion can search/read fixture (and, manually, live Mail after FDA).

YAGNI: no draft UI, no approval queue, no policy authoring, no pairing wizard yet.

## Comments

- Claimed on `proto/companion-read-ui`. Three layouts live in `MailGent/Prototype/` behind a floating A/B/C switcher. Menu bar extra launches a detached `Window`; `LSUIElement = YES`. Fixture data is always available. Live Mail is a control-first toggle after FDA.
- HITL pick: **A Control-first**. Shell: popover stays launcher; layouts live in a detached window.

## Inputs

- [03 · MailboxIndex and ReadAPI TDD](03-mailbox-index-read-api.md)
- Product ticket 09: `.scratch/mailgent-product-definition/issues/09-prototype-mailbox-navigation.md`
- Product ticket 12: `.scratch/mailgent-product-definition/issues/12-define-human-mail-baseline.md`
