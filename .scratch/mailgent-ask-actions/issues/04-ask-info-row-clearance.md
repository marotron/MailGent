# 04 · Ask help-row equal clearance

Type: task  
Status: open  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/24

## Question

How should the Ask access-lead help row get equal vertical clearance above and below (title bar → row → first card)?

## Notes

- Shipped in 0.11.2 with centered larger `?` + callout; top gap reads slightly taller than bottom.
- Likely SF Symbol optical padding and/or chrome `pad` vs VStack `gap` mismatch — keep fix scoped to Ask help row.
- Separate from button cursor (#23) and Rules-from-Ask / redact work.
