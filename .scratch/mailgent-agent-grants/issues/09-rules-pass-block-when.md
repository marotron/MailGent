# 09 · Rules (Pass + Block + When)

Type: task  
Status: claimed  
Blocked by: —

## Question

Expand Passes into a Shared **Rules** tab: keep Pass green-lights, add Block withhold, add optional When date window. Letters shared across polarities.

## Product lock

| Concept | Meaning |
|---------|---------|
| Tab | **Rules** (was Passes) |
| Pass | Conditional green light — union fields on match (circled ✓) |
| Block | Conditional withhold — subtract fields on match (circled ✗) |
| When | Optional After/Before day window; AND\|OR with From/Subject |
| Letters | One A–Z pool across Pass + Block |
| Persist | `rules.json` (`rules` + `enablements` with `ruleID`; synthesized Codable) |

- Blocks apply after Passes (withhold wins)
- Base allow still required — rules never open the gate
- Scope chips attach both polarities

## Seams

1. `RuleEngine` — polarity, When match, `subtracting`
2. `PassDeskPane` — Rules list/editor, When toggle, circled marks
3. Grant Desk tab rename + Access preview notes
4. `rules.json` round-trip (polarity + When + `ruleID`)

## Proto

`.scratch/mailgent-agent-grants/examples/prototype-pass-block-rules.html` · variant A locked.
