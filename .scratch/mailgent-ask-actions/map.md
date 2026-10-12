# Ask actions (Rules-from-Ask + redact)

Label: wayfinder:map

## Destination

Ship optional **Rules-from-Ask** on the conditional Ask dialog (create **or update** Pass/Block for future mail; current `get` still needs Allow/Block). Then **manual redact-then-Allow** as a one-shot body override. Spec both up front; prototype and implement Rules-from-Ask first.

## Notes

- Ask today: `ConditionalAccessPromptDialog` + `DetachedWindowHost.runConditionalAsk` → binary `ConditionalAccessDecision`.
- Rules today: Grant Desk Rules tab → `rules.json` + enablements via `AgentBridge` / `RuleEngine`.
- Spec: [`spec.md`](spec.md).
- Proto: [`examples/prototype-ask-create-rule.html`](examples/prototype-ask-create-rule.html).

## Decisions so far

- Product lock captured in [`spec.md`](spec.md) (ship order, optional rule, fail-closed close, reuse `GrantRule`, redact one-shot).
- Ask can **New** or **Existing** (edit shared `rules.json` rule in place); disclosure copy → “Also manage a rule…”.
- Future / deferred tickets mirror to **GitHub Issues** (QuotAI pattern: labels `roadmap` / `fog` / `next-version`) — see `docs/agents/issue-tracker.md`.
- Rules-from-Ask → [#21](https://github.com/marotron/MailGent/issues/21) · [issues/01-rules-from-ask.md](issues/01-rules-from-ask.md) — prototype in progress (claim).
- Manual redact then Allow → [#22](https://github.com/marotron/MailGent/issues/22) · [issues/02-manual-redact-then-allow.md](issues/02-manual-redact-then-allow.md) — deferred (`next-version`); blocked on 01 / #21.

## Fog

Active grilling lives on GitHub (prefer links over duplicating questions here):

- Rules-from-Ask open questions → [#21](https://github.com/marotron/MailGent/issues/21) (`roadmap`, `fog`)

## Deferred

- Manual redact then Allow → [#22](https://github.com/marotron/MailGent/issues/22) (`roadmap`, `next-version`) · [issues/02-manual-redact-then-allow.md](issues/02-manual-redact-then-allow.md) — blocked on 01 / #21

## Out of scope

- Auto-Allow / Auto-Block when saving a rule
- Opening Grant Desk from Ask
- Agent MCP tools for redaction
- Changing RuleEngine match semantics
