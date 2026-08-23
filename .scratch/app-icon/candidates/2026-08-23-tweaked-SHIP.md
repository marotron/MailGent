# Ship candidate `2026-08-23-tweaked`

The user chose this in the icon tweaker **to add to the app**. Follow the checklist below now.


## Files (already in repo)

- SVG `.scratch/app-icon/candidates/2026-08-23-tweaked.svg` — **full 1024 plate**, glyph already on the 824 keyline
- PNG `.scratch/app-icon/candidates/2026-08-23-tweaked.png`
- Template (menu bar) `.scratch/app-icon/candidates/2026-08-23-tweaked-template.svg` + `-template.png` — black glyph, alpha holes, no plate
- State `.scratch/app-icon/candidates/2026-08-23-tweaked.json`
- Pick `.scratch/app-icon/pick.json`

## Hard rules

- Master is **full-1024**. Resize appiconset slots from the PNG. **Do not** run `Scripts/AppIcon/stamp_from_png.swift` (double inset ≈ 66% crop).
- Do not use Icon Composer MCP `export_preview`.
- Sparkles in this candidate: **custom-fill**. Envelope: **shadow-only**.
- This tweaker is **flat**. Do not invent a glass `.icon` rewrite unless the user asks for glass after this ship.
- Canonical procedure: `docs/agents/app-icon.md`.

## Checklist (only if shipping)

1. Confirm `pick.json` slug is `2026-08-23-tweaked`.
2. Resize `2026-08-23-tweaked.png` into `MailGent/Assets.xcassets/AppIcon.appiconset/` (same filenames, no extra keyline):
- icon_16x16.png (16px)
- icon_16x16_2x.png (32px)
- icon_32x32.png (32px)
- icon_32x32_2x.png (64px)
- icon_128x128.png (128px)
- icon_128x128_2x.png (256px)
- icon_256x256.png (256px)
- icon_256x256_2x.png (512px)
- icon_512x512.png (512px)
- icon_512x512_2x.png (1024px)
3. Pack icns: copy those PNGs into a temp `.iconset` named `icon_*.png`, then `iconutil -c icns` → `MailGent/Resources/AppIcon.icns`.
4. Skip `Design/IconPack/MailGent.icon` / `AppIcon.icon` unless the user asked for Liquid Glass on this mark.
5. Skip `test_app_icon.swift` — that test is for glyph-in-keyline Era A masters; a full-bleed plate will fail it on purpose.
6. Do not run Liquid Composer / `export-mailgent.mjs` for this flat candidate.
7. Menu-bar template + `menuBar` pulse spec in the JSON are **preview + pack only**. Live app still uses SF Symbol `tray.full` (`MenuBarIcon.swift`). Do not swap the status item unless the user asks. Success pulse: sparkles fill green, light large → mid → small, then fade.

## Do not

- Stamp, MCP preview, or compile a different candidate than `2026-08-23-tweaked`.
