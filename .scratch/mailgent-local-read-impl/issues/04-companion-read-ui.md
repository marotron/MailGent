# Companion Read UI Prototype Then Shell

Type: prototype
Status: resolved
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

## Inputs

- [03 · MailboxIndex and ReadAPI TDD](03-mailbox-index-read-api.md)
- Product ticket 09: `.scratch/mailgent-product-definition/issues/09-prototype-mailbox-navigation.md`
- Product ticket 12: `.scratch/mailgent-product-definition/issues/12-define-human-mail-baseline.md`

## Answer

**Keep A Control-first.** Menu-bar popover is the launcher; layouts live in a detached `Window`. Prototype chrome stays on `proto/companion-read-ui` (`b7252e6`); first-ship shell is `feat/04-companion-shell`.

### HITL

- Layout: **A — Control-first** (health + placements land; search is a separate destination). Not B Search-first, not C Review desk.
- Shell: compact `MenuBarExtra` popover (status + Open Companion) launches `Window(id: "companion")`. Not popover-as-primary.

### Prototype (`proto/companion-read-ui`)

`MailGent/Prototype/PrototypeReadRoot` + floating A/B/C switcher over fixture `ReadAPI` data:

- A Control-first — dashboard, then NavigationStack search/read
- B Search-first — hero search + NavigationSplitView detail
- C Review desk — HSplitView queue + inspector

### Shell (`feat/04-companion-shell`)

- `LSUIElement = YES`; no `WindowGroup`; `MenuBarExtra` + `Settings` + detached `Window`
- Control center: FDA health, last ingest, placement list, Search mail
- Fixture ingest by default; live `~/Library/Mail` toggle after FDA
- Partial marked; empty body `not_available`; Open in Apple Mail fails closed (Message-ID not indexed)
- `make test` green; `make run` launches the menu-bar app

## Comments

- HITL pick recorded after running the proto switcher.
