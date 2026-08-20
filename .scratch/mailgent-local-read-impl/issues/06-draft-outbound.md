# Draft Outbound Prototype

Type: prototype
Status: claimed
Blocked by: 05

## Question

Does copy-paste into Mail.app preserve the agent-companion value, or does a MailGent-owned versioned draft ledger earn its complexity?

## Context

**Branch:** `proto/draft-outbound` only after ticket 05. Keep off `main` after capture.

No Mail-store writes, no AppleScript, no `mailto:` unless this prototype rejects copy-paste.

Two (max three) throwaway variants on one prototype surface, full state visible after each action:

- **A** Copy current reply text to clipboard; user pastes in Mail.app.
- **B** Local ledger: create/edit versions; show history; copy *current* version; still no Mail-store write.
- Optional **C** only if A/B both fail in your hands.

**Stop and ask.** If A wins: document it, no ledger code on `train/local-read`. If B wins: new `feat/07-draft-ledger` with TDD at a new **DraftLedger** seam (create/update/list versions/copy), then a thin MCP `create_draft` / `update_draft` wrapping the ledger. Send/mutation approvals stay out.

## Verify

A variant is picked in writing on this issue. Ledger lands on the train only if B wins.

YAGNI: no send, no Mail.app scripting, no approval queue.

## Comments

- 2026-08-20 — Claimed on `proto/draft-outbound`. Throwaway A/B surface: `PrototypeDraftRoot` + switcher. A = clipboard → Mail.app; B = in-memory version ledger then copy. `make prototype-draft` (or `make run` on this branch). **Stop and ask** which wins before any train work.

## Inputs

- [05 · MCP Read, Pairing, Grants, Audit](05-mcp-pairing-grants-audit.md)
- [Decide Local-Mode Product Posture](../../mailgent-local-mode/issues/02-decide-local-mode-posture.md) — outbound was deferred to this ticket
