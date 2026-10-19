# 01 · Adopt traffic-sign Pass/Block marks

Type: task  
Status: open  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/26

## Question

Replace green-tick / red-X rule marks with `docs/agents/assets/rule-pass.svg` and `rule-block.svg` everywhere a **final rule decision** is shown.

## Product lock

See [`docs/agents/handoff-rule-indicators.md`](../../../docs/agents/handoff-rule-indicators.md).

- Pass: UK blue `#005EA5` + white ahead arrow (not a green tick)
- Block: red `#C8102E` + white dash
- Neutral grey for not-evaluated
- Do not reuse Pass for validation / HTTP ok

## Seams

1. Shared Swift mark view from SVG/PDF assets
2. Retarget `RuleNickChip`, `AccessLogRuleHitBadge`, `RuleFieldMarkChip`, `AccessTabRuleCountBadge`, polarity picker
3. Align `RuleMarkStyle` colors to handoff hex
4. Update `docs/ui-inventory.md`

## Assets

- `docs/agents/assets/rule-pass.svg` / `.png`
- `docs/agents/assets/rule-block.svg` / `.png`
- Issue preview strip: `../assets/target-rule-marks.png`

## Comments

### 2026-10-12

Mirrored to GitHub [#26](https://github.com/marotron/MailGent/issues/26) (`enhancement`, `roadmap`, `next-version`) with images.
