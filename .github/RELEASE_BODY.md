## Install

**Pre-release alpha** — not a stable or beta build. Version in the app bundle is semver (`0.3.0`); GitHub release title and About show **`0.3.0 alpha`**.

1. Download `MailGent-*.dmg` below.
2. Open the disk image and drag **MailGent** to **Applications**.
3. Launch from Applications (menu bar only — no Dock icon).

## macOS Gatekeeper warning

**This DMG is unsigned/ad-hoc unless the release workflow had `MAILGENT_SIGN_IDENTITY` and `MAILGENT_NOTARY_PROFILE` repository secrets set.** On other Macs, Gatekeeper may block or warn on first open (*“cannot be opened because the developer cannot be verified”* or similar).

To open anyway:

- **System Settings → Privacy & Security → Open Anyway**, or
- Right-click **MailGent** in Applications → **Open** → confirm **Open** once.

Notarized builds (Developer ID + Apple notarization on the personal Apple Developer account) will remove this step when signing secrets are configured.

## Requirements

- macOS 14+
- Apple Mail with mail already downloaded locally
- Full Disk Access or **Choose Mail Folder…** for live mail — see [README](https://github.com/marotron/MailGent#install--run)
