## Install

**Pre-release alpha** — not a stable or beta build. Version in the app bundle is semver (`@VERSION@`); GitHub release title and About show **`@VERSION@ alpha`**.

1. Download `MailGent-*.dmg` below.
2. Open the disk image — the window shows drag-to-Applications plus Gatekeeper notes.
3. Drag **MailGent** to **Applications**, then open it from Applications. If Gatekeeper blocks first launch, follow the optional steps on the background.

## macOS Gatekeeper warning

**This DMG is unsigned/ad-hoc unless the release workflow had `MAILGENT_SIGN_IDENTITY` and `MAILGENT_NOTARY_PROFILE` repository secrets set.** On other Macs, Gatekeeper may show *“MailGent Not Opened”* / *“was blocked to protect your Mac”* on first launch.

**On the DMG window:**

1. Drag **MailGent** → **Applications**, then open MailGent from Applications
2. If blocked (optional): click **Done** → **System Settings** → **Privacy & Security** → **Open Anyway** → confirm → **Touch ID** / **password**

Notarized builds (Developer ID + Apple notarization on the personal Apple Developer account) will remove this step when signing secrets are configured.

## Requirements

- macOS 14+
- Apple Mail with mail already downloaded locally
- Full Disk Access or **Choose Mail Folder…** for live mail — see [README](https://github.com/marotron/MailGent#install--run)
