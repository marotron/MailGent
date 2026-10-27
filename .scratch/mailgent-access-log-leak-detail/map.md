# Access Log · leak badge detail

Label: wayfinder:map

## Question

When leak guard fires, Access Log already shows a purple `leak` badge + count on the message meta row. Should clicking that badge reveal the detection list, and should the same badge also appear on the field label line (e.g. Body next to “user allowed (cached)”)?

## Status

- **Decision:** Variant A shipped (Access Log leak detail → 0.19.0).
- **GitHub:** no issue filed (feature shipped from wayfinder). Related but different: [#27](https://github.com/marotron/MailGent/issues/27) icon/color unify, [#43](https://github.com/marotron/MailGent/issues/43) Ask cache mark.
- **Prototype:** [`examples/prototype-leak-badge-detail.html`](examples/prototype-leak-badge-detail.html) — Variant A locked; B/C were explore-only.

## Shipped (Variant A)

- Message-level leak badge toggles the full detections panel between the meta row and `MessageAccessCard`.
- Subject / Body compact leak badges (after Ask chips, before rule chips) toggle the same panel filtered to that field.
- No popover. List rows: numbered index · code original → replacement · field / rule / mode badges; `Body:N` when `AuditLeakDetection.line` is set; redacted mode + `[REDACTED]` = light text on solid purple.
- Mode SF Symbols: `eye.slash.fill` / `arrow.left.arrow.right` / `shield.slash.fill` / field `doc.text`.

## Fog

_(cleared — Variant A locked and shipped.)_
