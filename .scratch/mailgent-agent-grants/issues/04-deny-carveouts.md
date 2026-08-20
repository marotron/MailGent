# Explicit Deny Carve-Outs

Type: task
Status: resolved
Blocked by: 03

## Question

Can an explicit deny grant subtract matching messages from a broader allow (deny wins), without treating “no grant” as the same thing as Deny?

## Context

**Branch:** `feat/01-persist-grants` (stacked).

`effective = allows − denies`. Deny uses the same selector matching as allow. Absence of grant remains deny-by-default; Deny is only for carving out of a broader allow.

Persist deny rows with allows (01). UI: add Deny on a placement/participant from the companion card; desk polish in 06.

## Verify

Allow whole account + deny one mailbox → that mailbox never appears. Deny alone with no allow → still empty (not a special channel).

YAGNI: no smart-folder-backed denies yet.

## Inputs

- [07 · Agent authorization](../mailgent-product-definition/issues/07-define-agent-authorization.md)
- [10 · Policy authoring](../mailgent-product-definition/issues/10-prototype-policy-authoring.md) — explicit Deny carve-outs

## Answer

Yes. `Grant.mode` allow|deny; evaluation `allows − denies`. Companion **Deny carve-out mode** checkbox writes per-mailbox denies. Deny alone grants nothing.

## Comments

- 2026-08-20 — Resolved; `make test` green.
