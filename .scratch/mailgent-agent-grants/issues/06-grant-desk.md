# Grant Desk UI

Type: task
Status: resolved
Blocked by: 05

## Question

Can the companion ship the locked policy-authoring IA (wizard A + grant desk B) for data grants — inspect, edit, revoke, allow/deny — without rebuilding three throwaway web variants?

## Context

**Branch:** `feat/01-persist-grants` (stacked).

## Answer

**Lean desk shipped** (not a pixel port of the HTML prototype).

- Detached **Grant desk** window: Scope + Access tabs
- Scope: account/mailbox allows, From/date narrow, deny carve-out mode, clear all
- Access: body cap for next allow + active grant summary
- Control center: **Open grant desk…** + grant count

Deferred vs HTML prototype: dual-pane agent list, nested grant rows, wizard A first-run, Test pre-save counts, attachment caps UI.

## Comments

- 2026-08-20 — Lean desk on `feat/01-persist-grants`; full HTML fidelity left as fog.
