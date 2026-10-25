# DMG install window assets

Used by `Scripts/release/dmg.sh` for the Finder install window (drag → Applications, plus Gatekeeper copy).

| File | Role |
|------|------|
| `background.png` | Finder window background (920×824 @ 144 DPI = 460×412 logical; Retina) |
| `DS_Store` | Optional Finder layout blob (written by first local `make dmg`; used on CI) |
| `export.html` | Source for re-rendering the background |
| `render-background.swift` | Regenerates `background.png` (also prints icon-slot centers) |

Live Finder icons on the volume: **MailGent.app** and **Applications** only. No helper applets — unsigned helpers get Gatekeeper-blocked the same way as the app.

## Install steps on the background

1. Drag **MailGent** → **Applications**, then open MailGent from Applications
2. If Gatekeeper blocks (optional): **Done** → System Settings → Privacy & Security → **Open Anyway** → unlock

## Re-render background

```bash
swift Scripts/release/dmg-assets/render-background.swift
```

Copy printed `icon-slot centers` into `dmg.sh` (`ICON_*`) if the layout moved. Delete `DS_Store` and run `make dmg` so Finder layout regenerates.
