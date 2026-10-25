# Pretty DMG + Gatekeeper install UX

**When:** Packaging or documenting unsigned / ad-hoc MailGent releases.  
**Follow:** [`Scripts/release/dmg-assets/README.md`](../../Scripts/release/dmg-assets/README.md), [`ci-cd.md`](ci-cd.md), `.cursor/rules/versioning.mdc`.

## What ships

The Release DMG Finder window shows a **2/3 drag + 1/3 Open** row plus short Gatekeeper text (no screenshots, no helper applets):

| Icon | Role |
|------|------|
| `MailGent.app` | Drag to Applications |
| `Applications` | Symlink to `/Applications` |
| `Open MailGent` | Finder alias → `/Applications/MailGent.app` |

Background is a **2× Retina** PNG measured from `#canvas` in `export.html`. Icon positions live in `Scripts/release/dmg.sh`.

## User-facing steps (document the same everywhere)

Keep README, `.github/RELEASE_BODY.md`, and the DMG background in sync:

1. Drag **MailGent** → **Applications**, then double-click **Open MailGent**
2. If macOS shows *Not Opened* (optional): click **Done** → **System Settings** → **Privacy & Security** → **Open Anyway** → confirm → Touch ID / password

## Rebuild assets

```bash
swift Scripts/release/dmg-assets/render-background.swift
rm -f Scripts/release/dmg-assets/DS_Store   # force Finder layout regen
make dmg
```

CI uses the checked-in `DS_Store` when AppleScript/Finder cannot run. `dmg.sh` keeps the staged `Open MailGent` bookmark unless `/Applications/MailGent.app` exists so a remake can succeed — never delete-then-fail (that emptied step 2 on `0.15.0` CI). Staging must run `SetFile -a A -t fapa -c MACS` (alias bit); type/creator alone left CI DMGs with a blank icon and “used by macOS” on `0.16.0`.

## Do not

- Ship helper applets / Settings shortcuts on the DMG (unsigned helpers hit Gatekeeper too)
- Stage the Open alias with plain `cp` (strips FinderInfo → opens as text)
- Stage with `SetFile -t fapa -c MACS` only (missing `-a A` → blank icon / “used by macOS”)
- Delete the staged Open alias before a remake is confirmed (CI has no `/Applications/MailGent.app`)
- Ship a 1× background on Retina — it draws at ~¼ size
- Leave `.background` / `.fseventsd` icons in the visible window (park off-canvas)
- Document a different Gatekeeper path than the DMG graphic
