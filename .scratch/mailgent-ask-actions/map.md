# Ask actions (Rules-from-Ask + redact)

Label: wayfinder:map

## Destination

Ship optional **Rules-from-Ask** on the conditional Ask dialog (create **or update** Pass/Block for future mail; current `get` still needs Allow/Block). Then **manual redact-then-Allow** as a one-shot body override. Spec both up front; prototype and implement Rules-from-Ask first.

## Notes

- Ask today: `ConditionalAccessPromptDialog` + `DetachedWindowHost.runConditionalAsk` → binary `ConditionalAccessDecision`.
- Rules today: Grant Desk Rules tab → `rules.json` + enablements via `AgentBridge` / `RuleEngine`.
- Spec: [`spec.md`](spec.md).
- Proto (ship UI): [`examples/prototype-ask-rule-right.html?variant=G`](examples/prototype-ask-rule-right.html) · also [`examples/prototype-ask-create-rule.html`](examples/prototype-ask-create-rule.html) · [`examples/prototype-ask-cache.html`](examples/prototype-ask-cache.html) · [`examples/prototype-ask-redact.html`](examples/prototype-ask-redact.html).

## Decisions so far

- Product lock captured in [`spec.md`](spec.md) (ship order, optional rule, fail-closed close, reuse `GrantRule`, redact one-shot).
- 2026-10-19: [#21](https://github.com/marotron/MailGent/issues/21), [#22](https://github.com/marotron/MailGent/issues/22), and [#41](https://github.com/marotron/MailGent/issues/41) share seams with custom endpoints [#32](https://github.com/marotron/MailGent/issues/32) — `agentID` identity, overlays before cache, rule save does not write the cache, redact stays one-shot. See spec **Cross-feature seams**.
- Ask can **New** or **Existing** (edit shared `rules.json` rule in place).
- 2026-10-20: UI lock → variant **G** (Subject/From picks · right editor · commit on Allow/Block). Variant A (left disclosure) was 0.12.0.
- Future / deferred tickets mirror to **GitHub Issues** (QuotAI pattern: labels `roadmap` / `fog` / `next-version`) — see `docs/agents/issue-tracker.md`.
- Rules-from-Ask → [#21](https://github.com/marotron/MailGent/issues/21) closed · [issues/01-rules-from-ask.md](issues/01-rules-from-ask.md) — shipped 0.12.1 (G) + 0.13.2 Enable on.
- Manual redact then Allow → [#22](https://github.com/marotron/MailGent/issues/22) · [issues/02-manual-redact-then-allow.md](issues/02-manual-redact-then-allow.md) — deferred (`next-version`).

## Fog

Active grilling lives on GitHub (prefer links over duplicating questions here):

- Ask cache **Selected agents** share (deferred from #41 close) — open a follow-up if needed
- Access log mark Ask cache reuse → [#43](https://github.com/marotron/MailGent/issues/43) (`roadmap`, `next-version`)

## Shipped (closeout)

- Rules-from-Ask → [#21](https://github.com/marotron/MailGent/issues/21) closed · 0.12.1 (G) + 0.13.2 Enable on · [issues/01-rules-from-ask.md](issues/01-rules-from-ask.md)
- Cache Ask Allow/Block → [#41](https://github.com/marotron/MailGent/issues/41) closed · 0.13.0 Remember Ask · [issues/05-cache-ask-for-same-message.md](issues/05-cache-ask-for-same-message.md) (Selected share still deferred)

## Deferred

- Manual redact then Allow → [#22](https://github.com/marotron/MailGent/issues/22) (`roadmap`, `next-version`) · [issues/02-manual-redact-then-allow.md](issues/02-manual-redact-then-allow.md)
- Ask button pointer cursor on hover → [#23](https://github.com/marotron/MailGent/issues/23) (`bug`, `next-version`) · [issues/03-ask-button-cursor.md](issues/03-ask-button-cursor.md)
- Ask help-row equal clearance → [#24](https://github.com/marotron/MailGent/issues/24) (`enhancement`, `next-version`) · [issues/04-ask-info-row-clearance.md](issues/04-ask-info-row-clearance.md)
- Access log Ask cache chip → [#43](https://github.com/marotron/MailGent/issues/43)
- Traffic-sign Pass/Block marks (consume from Ask too) → [#26](https://github.com/marotron/MailGent/issues/26) · [../mailgent-ui-icons/](../mailgent-ui-icons/)
- Unify icons/colors app-wide → [#27](https://github.com/marotron/MailGent/issues/27)

## Out of scope

- Auto-Allow / Auto-Block when saving a rule
- Opening Grant Desk from Ask
- Agent MCP tools for redaction
- Changing RuleEngine match semantics
