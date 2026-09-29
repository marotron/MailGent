# 08 · Passes (conditional field green lights)

Type: task  
Status: claimed  
Blocked by: —

## Question

Ship **Passes**: conditional field upgrades on already-allowed messages, matching the locked UX in `examples/prototype-smart-folders.html`.

## Product lock

| Concept | Meaning |
|---------|---------|
| Grant | Standing access for an agent on a placement |
| Pass | Conditional green light: on match, union fields onto an already-allowed message |

- UI name: **Passes** (not smart folders)
- Chip letter: A–Z; full name separate
- Not a visibility gate — base allow required first
- Field upgrade only; skip when base already covers pass fields
- Agents on the pass definition; enablement only on Scope placements
- Persist `passes.json` next to `grants.json`

## Seams (TDD)

1. `PassEngine` — match modes, within-OR, between AND/OR, field union, redundant skip, agent/placement filtering
2. `AgentReadAPI` + passes — after `GrantGate.effectiveFields`, upgrade on match; deny still empty
3. Pass persistence — `passes.json` definitions + enablements round-trip

## Out of scope v1

- Passes as allow/deny visibility
- Body/keyword/regex matchers
- New iconography

## Comments

- Plan: `.cursor/plans/passes_green_lights_9ceb5b8f.plan.md` (user home)
- Branch: `feat/passes`
