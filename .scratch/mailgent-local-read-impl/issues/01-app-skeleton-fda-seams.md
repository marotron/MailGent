# App Skeleton, FDA Onboarding, Confirm TDD Seams

Type: task
Status: open
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
