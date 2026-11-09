# await_ask — test plan

Scratch only. Every bullet = one red→green test (or script case). Synthetic fixtures only.
Seams confirmed: `PendingAskRegistry` · `AgentReadAPI` · `LoopbackMCPServer` · UI bridge · `Scripts/tests/await-ask/`.

Ship gate: matrix **A–E** green under `make test` / script self-check. Matrix **F** is explicit non-coverage.

---

## A. Registry — `PendingAskRegistryTests`

- [x] Submit creates `askId` + future `expiresAt`; hard deadline not reset on dedupe
- [x] Identical fingerprint while pending → same `askId`, one entry
- [x] Different field set / message / filename / agent → new ask
- [x] Soft await → `stillAwaiting` after soft timeout; entry still pending
- [x] Resolve `allow` / `block` wakes waiter with that outcome
- [x] Soft timeout then late resolve → next await sees terminal outcome (retention)
- [x] Hard expire → `expired`; waiters woken; UI expiry handler invoked
- [x] `supersede` → `superseded`; not `block` / not `expired`
- [x] No waiter left ≠ cancel; hard expiry still runs
- [x] Dropped soft-wait continuation must not resolve/cancel entry
- [x] Wrong `agentID` on await / claim → `unknown` (not other agent’s outcome)
- [x] Unknown / past retention → `unknown`
- [x] After `allow`, lease claim succeeds for exact fingerprint+agent+askId
- [x] Lease claim idempotent (second re-get same fingerprint still allowed within TTL)
- [x] Lease rejects different message / fields / agent / askId
- [x] Soft clamp 1…120; soft wait capped by remaining hard; default soft constant is 25
- [x] Soft/hard sleeps use injected clock seam (no wall-clock flake); advancing clock expires
- [x] `supersedeMatching` supersedes pending asks by predicate

---

## B. Read policy — `AgentReadAPITests`

- [x] Grant On / no Ask → normal payload, no `askId`, no registry submit (existing)
- [x] Prompts disabled → Ask fields denied as today, no `askId` (existing)
- [x] Ask needed → returns pending signal + `askId` without awaiting human
- [x] Unbound prompter → fail closed (deny / error), never auto-allow
- [x] Re-get with valid lease + cache **disabled** → body for allowed fields, no second dialog
- [x] Re-get after allow with **lost first response** → second re-get still lease-hit (idempotent)
- [x] Re-get after `block` → denied/sanitized shape, no body for blocked Ask fields
- [x] Re-get after `expired` → fail closed for those Ask fields
- [x] Re-get after `superseded` without new evaluation → no silent body; agent must new `get` path
- [x] Mid-flight grant/rule change: lease path still re-evaluates grants, rules, leak-guard, message existence before body
- [x] `get_attachment` Ask (`limitingAskTo` Attachment content) → pending envelope; fingerprint includes filename
- [x] Decision cache still optional: when enabled, Allow may also cache; lease remains source of truth for this askId transaction (existing cache tests + lease test)


---

## C. MCP wire — `LoopbackMCPServerTests`

- [x] `get` Ask → normal result `status: awaiting_user` + `askId` + `expiresAt` + `pendingFields` (not `isError`)
- [x] Open returns before human decides (non-blocking; controlled fake clock / immediate prompter hold)
- [x] `await_ask` default soft timeout is **25** when arg omitted
- [x] Soft poll → `awaiting_user`; not audited by default
- [x] Soft poll audited when shared “Log soft-wait polls” on
- [x] Terminal `allow` / `block` / `expired` / `superseded` audited as `await_ask`
- [x] Unknown `askId` → error string parallel to propose_send unknown
- [x] Wrong-agent `askId` → unknown/error, not cross-agent leak
- [x] Tool list exposes `await_ask`; description mentions client-budget soft timeout
- [x] Identical second `get` while pending → same `askId`
- [x] `get_attachment` pending ack includes `filename`

---

## D. UI / rematch bridge

- [x] Detached present after open; `get` HTTP already completed (`onConditionalAskOpened` → Task; nil blocking prompter)
- [x] Allow / Block → registry resolve (+ optional cache write) (`applyAskUIOutcome`)
- [x] Traffic-light / ⌘W → `block` (not `expired`) (existing `finishAsk(.block)` + registry resolve)
- [x] Hard expiry dismiss → `expired` (not `block`) (`expireConditionalAsk`; registry already `expired`)
- [x] Save rule → `rematchPendingAsks` → registry `superseded` for matching pending asks (`.recheck` → superseded)
- [x] Queue indicator still tracks open asks (same `AskQueueIndicator` + askId as request id)

---

## E. Scripted transport — `Scripts/tests/await-ask/`

- [x] Soft poll loop with `timeout=25` under ~30s client socket budget → no transport kill during soft wait (`fake_mailgent.py --self-check`)
- [x] Allow after prior soft `awaiting_user` → terminal allow → re-get body
- [x] Client disconnect / aborted await → Ask still pending; later await still works (no cancel-on-drop)
- [x] Dedupe: two identical opens → one askId
- [x] `superseded` → script re-gets and handles new evaluation
- [x] Unknown askId → structured failure

---

## F. Explicit non-coverage (do not pretend green = done)

- Live Grok Bot urllib defaults / remote-monitor loss
- Real human timing / focus stealing
- Full AppKit window pixel tests
- Backport ownership fix for `await_propose_send`
