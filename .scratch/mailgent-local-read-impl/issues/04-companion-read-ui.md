# Companion Read UI Prototype Then Shell

Type: prototype
Status: open
Blocked by: 03

## Question

Which of three structurally different companion read layouts should first ship keep, and can that shell search/read fixture mail (and, manually, live Mail after FDA) without looking like Mail.app?

## Context

**Branches:** `proto/companion-read-ui` then `feat/04-companion-shell` off `train/local-read`.

Locked IA from product ticket 09: **control-first** default, not a Mail.app clone (Guideline 5.2.5). First-ship surfaces only: access health (FDA + last ingest), account/mailbox picker, search/read, open in Apple Mail if handoff works.

Prototype **sub-shape B**: a clearly named `PrototypeReadRoot` with **three structurally different** layouts and a floating variant switcher. Variants must differ in hierarchy (control-first vs search-first vs review desk), not color. Real fixture data behind all three.

**Stop and ask** which variant (or mix) to keep. Then implement only that on `feat/04-companion-shell`. Point this issue at the prototype branch; do not merge prototype chrome to `main`.

## Verify

A variant is picked; companion can search/read fixture (and, manually, live Mail after FDA).

YAGNI: no draft UI, no approval queue, no policy authoring, no pairing wizard yet.

## Inputs

- [03 · MailboxIndex and ReadAPI TDD](03-mailbox-index-read-api.md)
- Product ticket 09: `.scratch/mailgent-product-definition/issues/09-prototype-mailbox-navigation.md`
- Product ticket 12: `.scratch/mailgent-product-definition/issues/12-define-human-mail-baseline.md`
