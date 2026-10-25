# Pretty DMG + Gatekeeper install UX

**When:** Packaging or documenting unsigned / ad-hoc MailGent releases.  
**Follow:** [`Scripts/release/dmg-assets/README.md`](../../Scripts/release/dmg-assets/README.md), [`ci-cd.md`](ci-cd.md), `.cursor/rules/versioning.mdc`.

## What ships

The Release DMG Finder window shows a **drag → Applications** layout plus short Gatekeeper text (no screenshots, no helper shortcuts):

| Icon | Role |
|------|------|
| `MailGent.app` | Drag to Applications |
| `Applications` | Symlink to `/Applications` |

Background is a **2× Retina** PNG (`920×824` @ 144 DPI) for a `460×440` window (content `460×412`). Icon positions live in `Scripts/release/dmg.sh`.

## User-facing steps (document the same everywhere)

Keep README, `.github/RELEASE_BODY.md`, and the DMG background in sync:

1. Drag **MailGent** → **Applications**, then open MailGent from Applications
2. If macOS shows *Not Opened* (optional): click **Done** → **System Settings** → **Privacy & Security** → **Open Anyway** → confirm → Touch ID / password

## Rebuild assets

```bash
swift Scripts/release/dmg-assets/render-background.swift
rm -f Scripts/release/dmg-assets/DS_Store   # force Finder layout regen
make dmg
```

CI uses the checked-in `DS_Store` when AppleScript/Finder cannot run.

## Do not

- Ship helper applets / Settings shortcuts on the DMG (unsigned helpers hit Gatekeeper too)
- Ship a 1× background on Retina — it draws at ~¼ size
- Leave `.background` / `.fseventsd` icons in the visible window (park off-canvas)
- Document a different Gatekeeper path than the DMG graphic
