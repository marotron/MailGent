# App Skeleton, FDA Onboarding, Confirm TDD Seams

Type: task
Status: resolved
Blocked by:

## Question

Can a macOS SwiftUI app launch with Full Disk Access onboarding that fails closed, run `xcodebuild test`, and lock the six TDD seams in writing before any domain test is written?

## Context

**Branch:** `feat/01-app-skeleton` off `train/local-read`.

Create a macOS SwiftUI app + Swift Testing target. Two modules: `MailStore` (pure, fixture-driven) and `MailGent` (app + MCP). Entitlements/docs: Full Disk Access onboarding copy; fail closed with a clear “grant access to Mail” state. One command: `xcodebuild test` (or a `Makefile`/`mise` wrapper).

HITL: confirm the six seams below in writing on this issue. No test is written at an unconfirmed seam.

1. **MailStore** — given a fixture Mail tree, list accounts / mailboxes / messages; return body + flags; mark partial vs complete.
2. **MailboxIndex** — ingest a tree; report what is new on a second pass; `search` / `get` by id.
3. **ReadAPI** — `list` / `search` / `get` / `listPlacements` with cursor pages (~25, max 100). MCP tools wrap this; they are not a second domain.
4. **GrantGate** — deny-by-default; account/mailbox allow; denied messages omitted from results and counts (same generic `not_available`).
5. **Pairing** — named agent + credential; unsigned/wrong credential fails closed.
6. **AuditLog** — append-only read/search/auth events; inspect via API; no silent delete.

Context7: App Sandbox, TCC, Hardened Runtime, notarization.

## Verify

Empty app launches; tests run; FDA path documented; seams listed on this issue as confirmed.

YAGNI: no login-item helper, no Sparkle, no MAS path.

## Inputs

- [Decide Local-Mode Product Posture](../../mailgent-local-mode/issues/02-decide-local-mode-posture.md)
- [Research ArchMail and Apple Mail On-Disk Viability](../../mailgent-local-mode/issues/01-research-archmail-ondisk-viability.md)

## Answer

**Yes.** `feat/01-app-skeleton` (parent `train/local-read`) ships a macOS SwiftUI app + `MailStore` framework + Swift Testing. `make test` is the one command (`xcodegen generate` then `xcodebuild test`). App launched; 4 tests passed. No domain tests at the six seams — only a MailStore module smoke and fail-closed access snapshots.

### Seams confirmed (HITL 2026-08-19)

Confirmed as-is:

1. **MailStore** — fixture tree → accounts / mailboxes / messages; body + flags; partial vs complete
2. **MailboxIndex** — ingest; report what’s new on a second pass; `search` / `get` by id
3. **ReadAPI** — `list` / `search` / `get` / `listPlacements` with cursor pages (~25, max 100)
4. **GrantGate** — deny-by-default; account/mailbox allow; denied rows omitted (generic `not_available`)
5. **Pairing** — named agent + credential; unsigned/wrong credential fails closed
6. **AuditLog** — append-only read/search/auth events; inspect via API; no silent delete

### Full Disk Access path

Apple: *“Your app can’t automatically gain full disk access through an entitlement or with code: the person using your app must choose to grant access in System Settings > Privacy & Security.”* ([Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox))

| Choice | What we did |
| --- | --- |
| App Sandbox | **Off.** MAS requires it and has no Mail-folder entitlement. First ship is Developer ID, not MAS. |
| Hardened Runtime | **On** (`ENABLE_HARDENED_RUNTIME`). Required to notarize. ([Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution); [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)). Local Debug with ad-hoc sign may disable HR — expected. |
| Entitlements | Empty `MailGent/MailGent.entitlements`. No `com.apple.security.app-sandbox`. No FDA key exists. |
| Fail closed | Probe lists `~/Library/Mail`. Denied → **Grant access to Mail** (Open Full Disk Access, Choose Mail Folder…, Recheck). No mail is read until granted or a readable folder bookmark exists. |
| Bookmark fallback | `NSOpenPanel` + security-scoped bookmark (plain bookmark if scoped fails). Complements FDA; does not replace it. |

Onboarding copy lives in `GrantAccessView`. Probe/snapshot types live in `MailLibraryAccess.swift` (app, not MailStore — MailStore stays fixture-driven).

YAGNI held: no login-item helper, no Sparkle, no MAS sandbox path.

## Comments

- 2026-08-19 — HITL confirmed the six TDD seams as listed. Stage 1 implemented on `feat/01-app-skeleton`.
