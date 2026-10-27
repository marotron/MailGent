# MailGent

**0.19.0 alpha** — Let AI help with your email — without handing over your inbox. MailGent is a gatekeeper between Apple Mail and your AI agents: Cursor and Grok talk to it over local MCP, you choose the slice they can see, secrets are redacted on-device, and every request is logged.

**Early alpha.** Local Apple Mail read, per-agent grants, Ask prompts, leak guard, and a full access log work today. Agents can draft; they cannot send or delete. Gmail/Yahoo and remote agents are not in this build.

**Interactive demo:** [demo.html](https://marotron.github.io/MailGent/demo.html) — watch one agent request walk through Scope → Fields → Rules → Leak guard.

## Screenshots

Gallery still shows **v0.8.2** captures for core surfaces. Ask, Access requests, Remember Ask, and Settings have moved since then — re-capture with `make screenshots` when you next refresh the set. Extra stills (Settings, About, Companion Read, Access Log Formatted) are linked below.

<table>
  <tr>
    <td width="50%"><img src="docs/screenshots/menu-bar.png" alt="Menu-bar status"><br><b>Menu bar</b> <i>(v0.8.2)</i> — access, last ingest, connected agents, last agent call.</td>
    <td width="50%"><img src="docs/screenshots/control-center.png" alt="Control center"><br><b>Control center</b> <i>(v0.8.2)</i> — access health, ingest stats, one card per paired agent.</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/grant-desk-scope.png" alt="Grant Desk Scope"><br><b>Grant Desk · Scope</b> <i>(v0.8.2)</i> — allowed placements per agent, field caps, leak guard.</td>
    <td><img src="docs/screenshots/grant-desk-access.png" alt="Grant Desk Access"><br><b>Grant Desk · Access</b> <i>(v0.8.2)</i> — per-placement fields, presets, preview with leak guard applied.</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/grant-desk-rules.png" alt="Pass and Block rules"><br><b>Shared · Rules</b> <i>(v0.8.2)</i> — Pass / Block overlays by From and Subject.</td>
    <td><img src="docs/screenshots/grant-desk-privacy.png" alt="Leak guard detectors"><br><b>Shared · Privacy</b> <i>(v0.8.2)</i> — built-in detectors, custom filters, hit modes.</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/access-log.png" alt="Access log"><br><b>Access Log</b> <i>(v0.8.2)</i> — every agent call, with leak-guard and rule hit counts.</td>
    <td><img src="docs/screenshots/access-log-formatted.png" alt="Access log Formatted response"><br><b>Access Log · Formatted</b> <i>(v0.8.2)</i> — truth-first card of what the agent received (Preview / Open in Apple Mail).</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/access-log-json-pretty.png" alt="Access log JSON Pretty"><br><b>Access Log · JSON Pretty</b> <i>(v0.8.2)</i> — exact response the agent received.</td>
    <td><img src="docs/screenshots/settings-general.png" alt="Settings General"><br><b>Settings · General</b> <i>(v0.8.2)</i> — loopback port, agent open-in-Mail, conditional Ask (Remember Ask is newer).</td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/settings-access.png" alt="Settings Access"><br><b>Settings · Access</b> <i>(v0.8.2)</i> — mail folder / Full Disk Access, purge access log.</td>
    <td><img src="docs/screenshots/about.png" alt="About MailGent"><br><b>About</b> <i>(v0.8.2)</i> — version + bundled changelog.</td>
  </tr>
</table>

More in [`docs/screenshots/`](docs/screenshots/) (including Companion Read and JSON Raw). Personal data in the screenshots (addresses, account IDs, search terms) is replaced with sample values.

## Features

What this alpha can do today. Fold new `CHANGELOG` items into the matching section on each bump.

### Local mail

- Reads Apple Mail on your Mac (`.emlx` under `~/Library/Mail`) — nothing is uploaded by MailGent
- On-device search index (SQLite FTS)
- Incremental ingest shows arrivals vs removals (e.g. `+44 −2277 → −2233`); Trash/Junk copies are not counted as new
- Menu bar and Control Center show access health, last ingest, and last agent call

**Debug builds** can use fixture mail. **Release builds use live Mail only.** Live Mail needs a readable `~/Library/Mail` (Full Disk Access, or Choose Mail Folder…).

### Agents (MCP)

- Pair **Cursor** and/or **Grok Bot** as separate machine-local agents (each gets its own Bearer)
- Loopback only: `http://127.0.0.1:8788/mcp` — change the port in Settings → General (avoid 8787; reserved for Cursor OAuth callbacks)
- Control Center agent cards: Show / Hide MCP config, Copy Bearer / Copy MCP config, revoke with confirmation; paired agents show as glyphs in the menu bar
- Agents talk to MailGent over MCP; MailGent has no built-in AI
- Optional Settings → General → **Allow agents to open messages in Apple Mail** (off by default) enables MCP `open_in_mail`
- MCP `get` returns `mailURL` (`message://…`) and `internetMessageID` when the message has an RFC Message-ID (fail closed when missing)

### Grants — what each agent may see

- Per agent: which mailboxes, From/To/date filters, deny carve-outs
- Per field: Subject, From, To, Cc, Date, Body, attachments — each **Off**, **Ask**, or **On** (cycle chips through all three)
- When **Allow conditional access prompts** is off, Ask fields show and act as Off; saved Ask choices return when you turn it back on
- Attachment Names Off clears Attachment Content; Content On turns Names On
- Attachment content: when On, `get_attachment` can write a local temp file for the agent (25 MiB cap); when Ask, the same tool prompts Allow / Block for that message

### Ask — approve before sharing

- Set a field to **Ask** when you want a human decision each time (not a standing Yes)
- Turn on **Allow conditional access prompts** in Settings (off by default)
- On MCP `get`, MailGent shows an on-device **Email access request** dialog (**Allow / Block**) with a message preview; blocked fields stay withheld
- On MCP `get_attachment` with Attachment Content on Ask, MailGent prompts for that field only; Allow/Block is remembered for the message until you restart
- A missing attachment filename returns `not_available` without prompting
- Help row names the agent; expand More for field / Allow·Block detail
- HTML-only Body shows an **HTML only** badge on the title row; plain preview is derived from HTML when needed
- Preview canvas has − / + zoom (default 75%); dialog height stays compact (~560pt max)
- Concurrent `get`s each open their own **Email access request** window. Allow, Block, or closing a window decides only that request
- Red badge on the menu-bar icon (and Dock when visible) shows how many access requests are waiting
- The status menu lists them under **Access requests** (count, one row each, **Block** / **Allow**). Clicking a row raises that window and does not decide it. Opening the menu raises every pending window without taking focus; closing it leaves the selected one in front
- Optional rule from Ask: Subject / From **Add to rule** picks open a right-pane editor (New or Existing). **Allow** / **Block** writes the rule when armed; closing the window still blocks this read without writing a rule
- Ask rule editor **Enable on**: This mailbox (default) or This account · all mailboxes for that agent
- Pass/Block field defaults from Ask keep Attachment content when names were already On on Scope (names ride along as the carrier bit)
- Long From / To / Cc lines stack display name then address badge when they do not fit side-by-side; **Add to rule** stays on the first line
- Optional **Remember Ask decisions** (Settings; shown when conditional prompts are on): reuse Allow / Block per field for the same message for **15 minutes**, **1 hour**, **24 hours**, **30 days**, **1 year**, **forever**, or **until MailGent quits**. Timed and forever answers persist locally in `ask-decisions.json` across relaunches; until quit stays in memory only. Default share is this agent only; optional All agents. Not a standing grant — new Ask fields still prompt; Pass/Block rules still win first. Forgetting an agent clears that agent’s entries from memory and disk

### Rules (Pass / Block)

- Shared Pass / Block overlays on mail that is already in scope (match From / Subject; optional When date window)
- Enable a rule per agent on a placement in Grant Desk
- From an Ask prompt, create or update a rule via envelope picks; enablement is the prompting agent plus that account and either the Ask mailbox or the whole account (Enable on)
- Matcher chips in the rule editor: copy the value to the pasteboard, or append that matcher onto another Pass/Block rule (same From or Subject field); works in view and edit
- Duplicate matchers in a rule (same mode + value) are flagged with orange chip chrome and a warning mark

### Leak guard

- Optional on-device scan of subject/body before the agent receives mail (opt in per placement)
- Built-in detectors plus your own filters; hits can redact or withhold
- Phone detector skips date-like runs, decimal ranges, and bare long IDs (e.g. `26-10-2026 14`, `12.71 - 12.71`, meeting IDs) that used to false-positive
- Credit-card detector requires a Luhn check; password patterns redact only the secret value (`password: …`), while `token=…` still redacts the whole assignment
- A match after an emoji (or any other multi-unit character) is redacted in place; that scan no longer quits the app
- Access Log records per-hit originals (and body line numbers on new entries) so you can inspect what was redacted or replaced

### Access log

- Every agent call is logged with exactly what the agent received (sanitized / withheld overlays)
- Request / Response modes: **Formatted** (default), **JSON Pretty**, or **JSON Raw**
- List chips for Ask allow/block and Pass/Block hits; Preview and Open in Apple Mail from the log (Companion Read and Access Log use the same Open in Apple Mail handoff when Message-ID is present)
- Remember Ask reuse uses a clock-arrow mark (`clock.arrow.circlepath`) instead of the live Ask `questionmark.circle.fill` — list chips, field badges (optically padded), and Formatted “user allowed (cached)”; same green allow / red block colors
- Leak badge on Formatted get / expanded search cards toggles a detections panel (message-level = all hits; Subject / Body compact badges filter to that field). Rows: numbered original → replacement with field (`Body:N` when known), rule, and mode badges; redacted hits use a solid purple `[REDACTED]` chip
- Attachment **Preview** still opens for you when the agent was denied or the file is too large; the note under the card is about agent delivery, not your preview
- Agents cannot edit the log; you can delete all entries, or entries older than 24 hours, in Settings

### Companion

- About MailGent (app menu / menu item) with bundled changelog; menu-bar version label opens the changelog
- Companion Read: Open in Apple Mail for the selected message when it has an RFC Message-ID

### Drafts

- Agents can create/update drafts in a MailGent-owned ledger (in memory)
- Drafts are **not** written into Mail.app; no send from MailGent; drafts show in the Access Log

### Install (DMG)

- Pretty Finder install window: drag to Applications, plus short Gatekeeper instructions (text only)
- **Open MailGent** Finder alias in the DMG launches the app from Applications after drag-install (CI builds set the Finder alias bit so the icon and double-click work; Open slot aligns with the drag-row icons)
- Background is Retina-scaled so the guide fills the DMG window on HiDPI displays

## Not working yet

Do not advertise these as shipped:

- Gmail/Yahoo OAuth
- Send / move / trash
- Approval queue
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
make dmg             # package only
make release         # run tests, then package
make screenshots     # DEBUG: fixture + demo grants/rules (capture locally)
make screenshots-ci  # DEBUG: same, auto-write PNGs under dist/screenshots/
```

**CI:** pull requests and pushes to `main` run `make test` on GitHub Actions ([workflow](.github/workflows/ci.yml)). Full where/when map (tests + Release): [`docs/agents/ci-cd.md`](docs/agents/ci-cd.md).

Capture README / `docs/screenshots/` images **locally** with fixture fake data (`make screenshots`). Release tags strip screenshot-only scaffolding before the DMG. Full screenshot workflow: [`docs/agents/screenshots.md`](docs/agents/screenshots.md).

For Gatekeeper-safe distribution, set before `make dmg`:

```bash
export MAILGENT_SIGN_IDENTITY='Developer ID Application: …'
export MAILGENT_NOTARY_PROFILE='mailgent-notary'   # `xcrun notarytool store-credentials`
```

**GitHub Release:** push tag `vX.Y.Z` matching `MARKETING_VERSION` (e.g. `v0.1.8` for `0.1.8`). The [Release workflow](.github/workflows/release.yml) strips screenshot helpers, runs `make test`, builds the DMG, publishes a **pre-release** titled **`X.Y.Z alpha`**, and attaches the disk image. Notes start with that version’s section from `CHANGELOG.md`, then the install text in [`.github/RELEASE_BODY.md`](.github/RELEASE_BODY.md). Optional repo secrets: `MAILGENT_SIGN_IDENTITY`, `MAILGENT_NOTARY_PROFILE`.


```bash
git tag -s v0.1.8 -m "0.1.8 alpha"   # signed annotated tag → GitHub Verified
git verify-tag v0.1.8
git push origin v0.1.8
```

**Gatekeeper** (unsigned / ad-hoc DMGs on other Macs):

1. Drag **MailGent** → **Applications**, then double-click **Open MailGent** (or open from Applications)
2. If *Not Opened* (optional): click **Done** → **System Settings** → **Privacy & Security** → **Open Anyway** → confirm → Touch ID / password

The DMG window shows the same steps. GitHub Release notes repeat them ([`.github/RELEASE_BODY.md`](.github/RELEASE_BODY.md)). Agent notes: [`docs/agents/pretty-dmg.md`](docs/agents/pretty-dmg.md).

`make prototype-accounts` is a **dev CLI**, not part of the `.app`.

## Pair agents

In the companion, **Pair Cursor** and/or **Pair Grok Bot**. Same loopback URL (Settings → General for the port); each agent gets its own Bearer. Control Center cards expose Show MCP config, Copy Bearer / Copy MCP config, and revoke. Grok Bot shows a copyable MCP snippet for the host to wire itself. Grants are independent per agent in Grant Desk.

On first launch with no saved pairing, MailGent pairs **Cursor** automatically. If `~/.cursor/mcp.json` exists, MailGent writes (and on revoke removes) a `mailgent` entry with the loopback URL and Cursor's Bearer. A new agent has no grants, so it sees no mail until you allow mailboxes in Grant Desk.

Tools: `search`, `list`, `list_new`, `list_placements`, `get`, `get_attachment`, `open_in_mail`, `create_draft`, `update_draft`, `status`, `update`, `set_source`. `get` may include `mailURL` / `internetMessageID` when Message-ID is present. `open_in_mail` and `set_source` stay off unless Settings allows them.

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
- Menu bar icon polish (current SF Symbol status item; final mark and pulse animation TBD)
- Personal Apple Developer Program → Developer ID + notarized GitHub Release (Gatekeeper-friendly binary outside the App Store; ticket 16 still open). Mac App Store is hostile to `~/Library/Mail`
- In-app updates via Sparkle (check GitHub Releases, notify, user chooses to install)
- Homebrew cask of the same notarized Release artifact (custom tap first; `homebrew/cask` later)
- Later: remote/expiring sessions, `lan-inference`, iPhone/iPad, Microsoft/Proton

**Out of scope for v1:** built-in assistant, unattended remote inbox, replacing Apple Mail
