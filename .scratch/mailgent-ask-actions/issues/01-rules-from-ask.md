# 01 · Rules-from-Ask

Type: prototype  
Status: shipped in 0.12.1 (variant G)  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/21

## Question

How should the Ask dialog let a human optionally create a **new** Pass/Block rule or **modify an existing** one (future mail) without changing the Allow/Block decision for the current `get`?

## Product lock

See [`../spec.md`](../spec.md). Highlights (variant **G**):

- Subject / From **Add to rule** / **In rule** picks; first pick opens right editor
- Segmented **New** | **Existing** on the right (no left “Also manage a rule…” disclosure)
- Draft matcher values from picks auto-prefill; save with Allow/Block when non-empty (no in-panel Save)
- Polarity folded; defaults from decision (or keeps Existing) unless overridden
- Footer fate `+ add rule` / `+ update rule` + Edit rule / Close; commit on Allow/Block
- Close without Allow/Block → Block this read only; no rule write
- Flush chrome family shared with Preview · Open in Mail · AND/OR · Close

## Shared seams

Ship in any order with [#41](https://github.com/marotron/MailGent/issues/41), [#22](https://github.com/marotron/MailGent/issues/22), and [#32](https://github.com/marotron/MailGent/issues/32). Do not close these off:

- Enable the rule for the prompting pairing `agentID` + account + placement ([#31](https://github.com/marotron/MailGent/issues/31)). Name, icon, and MCP vs CLI are not the key. A second endpoint does not inherit this enablement.
- Allow / Block may write `rules.json` when armed. That write does not write the Ask cache.
- Overlays run before Ask. A field this rule sets On or Off does not prompt and does not read a cached decision, including on a later `get` of the same message.
- Redact ([#22](https://github.com/marotron/MailGent/issues/22)) stays off the rule. Do not persist a mask as Pass/Block fields.

## Seams (implementation after G lock)

1. Side-effect path Ask → `AgentBridge` (create **or** update + persist + enable) on Allow/Block when picks non-empty
2. Right-pane editor inside `ConditionalAccessPromptDialog` (reuse PassDeskPane patterns; do not open Grant Desk)
3. Tests: RuleStore create + update round-trip; Ask path still binary; enablement scoped
4. Docs: CHANGELOG / README only on version bump

## Proto

```bash
open ".scratch/mailgent-ask-actions/examples/prototype-ask-rule-right.html?variant=G"
```

Trials A–F stay in the proto. Ship UI is **G**. The right-hand strip is the seam: switch New/Existing, Allow / Block writes the rule when armed + the cache for this get, **get** applies the overlay before the cache.

## Out of scope

- Auto-Allow / Auto-Block on save
- Opening Grant Desk from Ask
- Changing RuleEngine match semantics

## Comments

### 2026-10-12

Mirrored to GitHub [#21](https://github.com/marotron/MailGent/issues/21) (`enhancement`, `roadmap`, `fog`).

### 2026-10-20

Locked ship UI to variant **G** (field picks · right editor · commit on decision). 0.12.0 remains the variant A ship.
