---
name: app-icon
description: >-
  Runs MailGent app icon and logo work as a candidate-first loop: sketch SVG,
  render PNG under .scratch/app-icon/candidates/, review with the user, ship
  into AppIcon only on explicit approval. Use when changing the app icon, logo,
  AppIcon.appiconset, AppIcon.icon, AppIcon.icns, liquid-composer layers,
  glass.html, ictool previews, or stamp_from_png.
---

# MailGent app icon

Follow [docs/agents/app-icon.md](../../../docs/agents/app-icon.md). Do not improvise a stamp-into-the-app shortcut.

## Hard rules

1. **No ship until named.** Do not write `MailGent/Assets.xcassets/AppIcon.appiconset`, `MailGent/Resources/AppIcon.icon`, or `MailGent/Resources/AppIcon.icns` unless the user says to ship a named candidate.
2. **Candidates first.** Every iteration is `.scratch/app-icon/candidates/YYYY-MM-DD-<slug>.svg` plus a `qlmanage -t -s 1024` PNG. Show that. Stop.
3. **One keyline.** Full 1024 plate masters (like `after.svg`) → resize slots, never `stamp_from_png.swift`. Glyph-only masters → stamp is OK. Never both (double inset ≈ 66% crop).
4. **No MCP `export_preview`.** It rewrites layer `scale` and crushes the glyph. Glass previews: `ictool` into `candidates/`.
5. **Sparkles default to holes** (plate through cream). Discs only if the candidate is explicitly discs.

## Loop

```text
edit candidate SVG
  → qlmanage PNG in candidates/
  → user reviews
  → optional ictool *-glass.png
  → "ship this" → then copy .icon, fallback PNGs, icns
```

Liquid Composer / `export-mailgent.mjs` is a **ship** tool, not a sketch tool.

## Tweaker API

```text
node .scratch/app-icon/api.mjs
→ http://127.0.0.1:8765/
→ GET /api/schema
```

Generate variants (`POST /api/variants` or CLI `variants --palettes all`), show the gallery, stop. User **Choose for the app** writes `.scratch/app-icon/pick.json` + `candidates/<slug>-SHIP.md`. Follow that brief only when they named the candidate to ship. Do not swap `MenuBarIcon.swift` (still `tray.full` template) unless asked.

Version files: **Save version** / **Load version** in the tweaker (`kind: mailgent-icon-version` JSON). CLI: `node .scratch/app-icon/api.mjs load FILE.json`.

Appearances: **Color**, **Mono**, **Menu bar**. Menu bar idle: per-layer AppKit gray ramp (`black` / `darkGray` / `gray` / `lightGray` / `white`), sparkle holes punch through. Pulses: Success / Error step timelines. Spec is `menuBar` + layer `menuBarInk` in the version JSON. Do not swap `MenuBarIcon.swift` unless asked.

## After ship

Canonical `.icon` is `Design/IconPack/MailGent.icon`. Copy to `MailGent/Resources/AppIcon.icon`. Keep `glass.html` appearances in sync.
