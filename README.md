# MailGent

**0.1.7 alpha** — macOS menu-bar companion beside Apple Mail. Not a daily client. No built-in AI. External agents talk to MailGent over MCP.

This is an **alpha**, not a beta. The first-ship slice is real (Apple Mail local-read, loopback MCP, grants, audit, in-memory draft ledger). Locked v1 still needs Gmail/Yahoo OAuth, mutation approvals, send/trash/hard-delete, remote agents, smart folders, and distribution.

## This release

- Apple Mail `.emlx` local-read from `~/Library/Mail`
- On-device SQLite FTS
- Incremental ingest reports arrivals vs removals (`+44 −2277 → −2233`); Trash/Junk copies are not counted as new
- Menu status times sit in chips; Changes shows the ingest window as `12:15–12:31 (16m)` (yesterday or the date when that window is not today); Last agent call uses clock + elapsed like Last ingest
- One paired `machine-local` agent on loopback `http://127.0.0.1:8788/mcp` (8787 reserved for Cursor OAuth callbacks)
- Grant desk: account/mailbox, From/To/date, deny carve-outs, field caps including Cc/body/attachments
- Append-only access log
- MailGent-owned draft ledger (in-memory; not written into Mail.app)

Default source is **fixture mail**. Live Mail needs a readable `~/Library/Mail` (Full Disk Access, or Choose Mail Folder…).

## Not working yet

Do not advertise these as shipped:

- Gmail/Yahoo OAuth
- Send / move / trash
- Approval queue
- Open in Apple Mail (stub)
- Keychain pairing
- Persisted drafts

## Requirements

- macOS 14+
- Xcode 16 / Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Apple Mail with mail already downloaded
- Access to `~/Library/Mail` (sandbox is off; [`MailGent.entitlements`](MailGent/MailGent.entitlements) is empty). Full Disk Access is one way; Choose Mail Folder… is enough for messages. Enable FDA if account names stay as UUIDs (`~/Library/Accounts`).

## Install / run

```bash
brew install xcodegen
make test
make run
make xcode
```

Menu bar only (`LSUIElement`). Settings → Access → Recheck, Open Full Disk Access, or Choose Mail Folder…

## Release (DMG)

Build a Release `.dmg` locally (output: `dist/MailGent-<version>.dmg`, version from `project.yml`):

```bash
make dmg        # package only
make release    # run tests, then package
```

For Gatekeeper-safe distribution, set before `make dmg`:

```bash
export MAILGENT_SIGN_IDENTITY='Developer ID Application: …'
export MAILGENT_NOTARY_PROFILE='mailgent-notary'   # `xcrun notarytool store-credentials`
```

**GitHub Release:** push a tag matching `MARKETING_VERSION` (e.g. `v0.1.7`). The [Release workflow](.github/workflows/release.yml) builds the DMG and attaches it. Optional repo secrets: `MAILGENT_SIGN_IDENTITY`, `MAILGENT_NOTARY_PROFILE`.

```bash
git tag v0.1.7
git push origin v0.1.7
```

**Gatekeeper:** without Developer ID signing and notarization, macOS may warn or block the app on first open on other machines. Use **Open Anyway** in Privacy & Security, or right-click → **Open**. GitHub Release pages include this warning in the release notes (see [`.github/RELEASE_BODY.md`](.github/RELEASE_BODY.md)).

`make prototype-accounts` is a **dev CLI**, not part of the `.app`.

## Pair Cursor

In the companion, **Pair Cursor** → paste the snippet into `~/.cursor/mcp.json`. The app can write that file with the Bearer.

Tools: `search`, `list`, `list_new`, `list_placements`, `get`, `create_draft`, `update_draft`, `status`, `update`, `set_source` (source switch is off unless Settings allows it).

## License

SPDX `Apache-2.0`. See [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE).

The names “MailGent” and the MailGent logos are trademarks of the copyright holder. Apache-2.0 does not grant trademark rights. Forks must rename.

Official binaries (when they exist) are notarized GitHub Releases. A Homebrew cask is **planned later** from that same file — not this alpha. No placeholder sha256.

## Warranty

Software is provided **AS IS**, without warranty of any kind, including fitness for a particular purpose. Mail may be lost or shown incompletely (partial `.emlx` files). This alpha does not mutate Apple Mail’s on-disk store. Time Machine or your provider’s Trash is your backstop, not a restore promise. Paired agents have their own practices — see [`PRIVACY.md`](PRIVACY.md). This license does not override consumer law where that law applies.

## Privacy

Device-first. See [`PRIVACY.md`](PRIVACY.md). Runtime data lives under `~/Library/Application Support/MailGent/`. Revoke pairing anytime.

## Roadmap

From the locked v1 spec and first-ship maps, not new invention:

- **Next train:** Gmail + Yahoo OAuth (keep local-read as a source). Yahoo commercial OAuth is still pending.
- Mutation approval queue (send, move, label, archive, flags)
- Soft delete → Trash (agent-proposeable + human). Hard/permanent delete per spec (stronger confirm; agent exposure as locked in ticket 08)
- Persistent draft ledger + companion draft UI; still no Apple Mail store writes on local-read
- Pairing polish, grant expiry, smart-folder selectors, Touch ID audit purge
- Developer ID + notarization (ticket 16 still open). Mac App Store is hostile to `~/Library/Mail`
- Later: remote/expiring sessions, `lan-inference`, iPhone/iPad, Microsoft/Proton

**Out of scope for v1:** built-in assistant, unattended remote inbox, replacing Apple Mail
