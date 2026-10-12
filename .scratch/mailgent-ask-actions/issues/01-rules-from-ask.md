# 01 · Rules-from-Ask

Type: prototype  
Status: claimed  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/21

## Question

How should the Ask dialog let a human optionally create a **new** Pass/Block rule or **modify an existing** one (future mail) without changing the Allow/Block decision for the current `get`?

## Product lock

See [`../spec.md`](../spec.md). Highlights:

- Optional collapsed “Also manage a rule…”
- Segmented **New** | **Existing** (picker + load for Existing)
- New: editable **Name** + **Nick** (letter); prefill From/Subject from envelope
- Existing: pick rule → load `GrantRule` (name/nick editable too)
- Match modes; Pass/Block; optional When; field chips (Ask defaults on New; keep rule fields on Existing)
- Save/Update → `rules.json` + enable for prompting agent/account/placement
- Footer stays **Block** | **Allow**; rule save does not dismiss

## Seams (implementation after proto lock)

1. Side-effect path Ask → `AgentBridge` (create **or** update + persist + enable) using prefilled/edited `GrantRule`
2. Compact editor inside `ConditionalAccessPromptDialog` (reuse PassDeskPane patterns; do not open Grant Desk)
3. Tests: RuleStore create + update round-trip; Ask path still binary; enablement scoped
4. Docs: CHANGELOG / README only on version bump

## Proto

`.scratch/mailgent-ask-actions/examples/prototype-ask-create-rule.html` · flip `?variant=`

## Out of scope

- Auto-Allow / Auto-Block on save
- Opening Grant Desk from Ask
- Changing RuleEngine match semantics

## Comments

### 2026-10-12

Mirrored to GitHub [#21](https://github.com/marotron/MailGent/issues/21) (`enhancement`, `roadmap`, `fog`).
