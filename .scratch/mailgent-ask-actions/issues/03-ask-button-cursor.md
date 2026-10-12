# 03 · Ask button pointer cursor

Type: task  
Status: open  
Blocked by: —  
GitHub: https://github.com/marotron/MailGent/issues/23

## Question

How should Ask dialog buttons (Allow / Block, Preview, Open in Apple Mail) show the standard macOS pointing-hand cursor on hover?

## Notes

- Observed on the live Ask window; controls work on click but cursor stays default arrow.
- Likely SwiftUI-in-AppKit HostedWindow cursor forwarding — keep fix scoped to Ask first, then decide whether to audit other Companion surfaces.
- Separate from Rules-from-Ask / redact / help-copy work.
