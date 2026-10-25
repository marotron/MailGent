# 02 · Unify icons and colors app-wide

Type: task  
Status: open  
Blocked by: 01  
GitHub: https://github.com/marotron/MailGent/issues/27

## Question

How do we lock one icon + color catalogue so Access Log, Grant Desk, Ask, and Companion never show the same job with different glyphs?

## Product lock

- Same job → same mark + color everywhere
- Rule Pass/Block consume #26 marks; Ask question-mark and leak shield stay distinct
- Catalogue lives in `docs/ui-inventory.md` (tokens + icon-per-job table)
- HTML protos must mirror the catalogue

## Seams

1. Inventory pass (grep SF Symbols + `RuleMarkStyle` call sites)
2. Catalogue section in `docs/ui-inventory.md`
3. Fix stragglers; keep secondary-action catalogue
4. Spot-check all major windows

## Open questions

- Keep green check for HTTP ok forever, or neutralize to reduce green overload?
- Third “not evaluated” glyph beyond grey outline?

## Comments

### 2026-10-12

Mirrored to GitHub [#27](https://github.com/marotron/MailGent/issues/27) (`enhancement`, `roadmap`, `next-version`) with Grant Desk + Access Log screenshots.
