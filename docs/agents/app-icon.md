# App icon / logo

Canonical procedure for MailGent mark work. Agents: load `.cursor/skills/app-icon/SKILL.md`. Archaeology of the old pipelines: `.scratch/app-icon/workflow.md`.

**Compile is a one-way door.** Do not write `AppIcon.appiconset`, `AppIcon.icon`, or `AppIcon.icns` until the user says to ship a named candidate.

---

## Loop

```text
edit SVG candidate
  → flat PNG in .scratch/app-icon/candidates/
  → user reviews
  → optional ictool glass PNG (same folder)
  → user says "ship this"
  → copy .icon, resize fallback PNGs, pack icns
  → then Xcode build
```

Until “ship this”, the app keeps the last **approved** icon.

Candidates:

```text
.scratch/app-icon/candidates/YYYY-MM-DD-<slug>.svg
.scratch/app-icon/candidates/YYYY-MM-DD-<slug>.png
.scratch/app-icon/candidates/YYYY-MM-DD-<slug>-glass.png   optional
```

Compare candidates on the desk (`qlmanage` PNG, `before.svg` / `after.svg`), not the Dock.

---

## What the running app uses

| Runtime | Path | When |
|---|---|---|
| Tahoe Liquid Glass | `MailGent/Resources/AppIcon.icon` | macOS that understands `.icon` |
| Fallback | `MailGent/Assets.xcassets/AppIcon.appiconset` + `MailGent/Resources/AppIcon.icns` | older Dock / Finder |

Build copies both via the **Ensure AppIcon assets** script in `MailGent.xcodeproj`. Canonical Tahoe bundle while designing: `Design/IconPack/MailGent.icon`. Copy to `Resources/AppIcon.icon` only at ship.

---

## Sketch vs ship

| | Sketch | Ship |
|---|---|---|
| Tool | SVG + `qlmanage -t -s 1024` | `ictool` (glass) then resize fallback |
| Output | `candidates/` | appiconset, icns, both `.icon` copies |
| Liquid Composer / Playwright | skip | optional pack export after approval |
| MCP `export_preview` | never (rewrites `scale`, crushes glyph) | never |

`ictool`: `Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool`

```text
ictool Design/IconPack/MailGent.icon --export-image \
  --output-file <candidates/...-glass.png> \
  --platform macOS --rendition Default --width 1024 --height 1024 --scale 1
```

Renditions: `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight`, `ClearDark`.

`ictool` 1.2 drops cubic `C` paths. Author sparkles as `L` polygons if they must survive glass.

---

## One keyline (do not double-inset)

Two masters. Pick one. Never both.

1. **Full 1024 icon** (plate fills the canvas, like `after.svg`, `rx=229`). Glyph is already on the 824 keyline via `scale(824/712) ≈ 1.157`. Resize to appiconset slots **without** `stamp_from_png.swift`.
2. **Glyph-only** (no plate). Then `Scripts/AppIcon/stamp_from_png.swift` is correct (draws into 824/1024).

`stamp_from_png` on an ictool / LC **full icon** PNG is the crop bug: `824/1024 × 824/1024 ≈ 66%`, extra gutter, mark looks clipped.

`test_app_icon.swift` asserts Era A keyline. Do not “fix” a full-bleed master by shrinking it to pass that test.

Icon Composer `position.scale` `1.2308` is `80 / 65` (LC units), not a zoom choice. Do not retune framing by editing that number unless the candidate SVG’s transform changed.

---

## Design defaults (until a candidate says otherwise)

- Sparkles are **holes** (plate colour through cream), same idea as `02-field.svg` evenodd. Gold discs are an experiment, not the default.
- Envelope: overcast shadow may stay; body rect and flap triangle are opt-in.
- Layer SVGs live in `Design/IconPack/liquid-composer/`. Same `viewBox="156 162 712 712"` on every file. Stack notes: `Design/IconPack/liquid-composer/README.md`.
- Tune knobs on the **candidate SVG** (opacity, shadow size, sparkle scale). Do not retune by hoping `splitIconGroups()` in `export-mailgent.mjs` will round-trip.
- Live layer tweaker + agent API: `.scratch/app-icon/tweaker.html` served by `node .scratch/app-icon/api.mjs` → [http://127.0.0.1:8765/](http://127.0.0.1:8765/). Per-layer colour / gradient / opacity. **Color / Mono / Menu bar** (per-layer AppKit gray ramp, alpha holes, no plate). `POST /api/variants` writes candidates. User **Choose for the app** writes `pick.json` + `SHIP.md` + zip pack. Still do not compile AppIcon until that pick (or an explicit “ship this”). Schema: `GET /api/schema`.

Preferred unshipped sketch (2026-08-23): `.scratch/app-icon/candidates/2026-08-23-after-tweaks.svg` — `after.svg` minus flap triangle and body rect, overcast + hole sparkles kept.

---

## Ship checklist

Only after the user names a candidate:

1. Copy approved geometry into `Design/IconPack/liquid-composer/` (and `.icon` assets if glass).
2. `Design/IconPack/MailGent.icon` is canonical; copy to `MailGent/Resources/AppIcon.icon`.
3. Fallback PNGs with the matching keyline rule (no double inset).
4. Pack `MailGent/Resources/AppIcon.icns`.
5. Update `Design/IconPack/glass-*.png` + `glass.html` to match the shipped mark.

---

## Fine-tune knobs (on the candidate)

| Knob | Where |
|---|---|
| Glyph scale | SVG transform or, after ship, `icon.json` `position.scale` |
| Overcast | path + `fill-opacity` |
| Envelope body / flap | include or drop |
| Sparkles | holes vs discs, size |
| Plate | `#4B617F → #7A8EAA` |
| Menu bar / B&W | Tweaker **Menu bar** appearance; per-layer black → dark gray → gray → light gray → white (`menuBarInk`). Files `*-template.svg`. Live status item is still SF Symbol `tray.full` until asked. |

Browser pad: `node .scratch/app-icon/api.mjs` then [http://127.0.0.1:8765/](http://127.0.0.1:8765/). Agent: `GET /api/schema`, `POST /api/variants`, `GET /api/pick`. If `pick.json` `"intent": "ship"` and the user chose that candidate for the app, follow its `SHIP.md`.
