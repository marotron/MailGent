# License, liability, Homebrew

Canonical MailGent policy for source license, user-facing disclaimers, and binary distribution. Agents: load `.cursor/skills/licensing/SKILL.md`. Do not re-open MIT vs GPL vs Apache unless the user explicitly changes this decision.

**Not legal advice.** This file tells agents what to put in the repo. It does not replace counsel.

---

## Decision (do not re-litigate)

| Choice | Value |
|---|---|
| Source license | **Apache License 2.0** |
| Attribution vehicle | Root **`NOTICE`** (required by Apache when we ship one) |
| Closed forks | **Allowed**, if they keep license + NOTICE credits |
| Name and icon | **Not licensed.** “MailGent,” the mark, and the app icon stay with the copyright holder. Forks rename. |
| Official binary | **Developer ID + notarized** GitHub Release only |
| Signing identity | **Personal Apple ID only** (`marotron@gmail.com` / marotron). Never company. |
| Homebrew | **Future.** Do not add a cask or tap until a notarized GitHub Release zip exists (paid personal Apple Developer Program). Then cask that same file — not `homebrew/cask` until a public hashed artifact exists. |

**Why Apache, not MIT:** same freedoms (use, fork, sell, close a fork) plus a real `NOTICE` duty, an explicit patent grant, inbound contributions under Apache unless stated otherwise, and an explicit “no trademark license.”

**Why not GPL/AGPL:** the owner wants credit on both open *and* closed products built from this code. Copyleft forbids the closed product; it does not put a credit on it.

**Why a license cannot “protect the idea”:** copyright covers this source and UI copy. A clean-room rewrite owes nothing. Trademark covers the name. Do not tell the user GPL or Apache fences the product category.

---

## When the user asks to apply the license

Create (do not paraphrase the Apache legal text):

1. **`LICENSE`** — the full [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.txt) body.
2. **`NOTICE`** — attribution the owner wants redistributors to keep. Ask for the copyright line (name, year) if missing; do not invent a company.
3. **README** — SPDX `Apache-2.0`; link `LICENSE` and `NOTICE`; one sentence that the **name and logo are trademarks** and forks must rename; official builds are the notarized GitHub Releases (and Homebrew cask when it exists).
4. Do **not** add a CLA unless the user asks (needed only if they later want to relicense the whole tree).

`NOTICE` shape:

```text
MailGent
Copyright YYYY <copyright holder>

This product includes software developed for MailGent
(https://github.com/marotron/MailGent).
The names "MailGent" and the MailGent logos are trademarks of
the copyright holder. Apache-2.0 does not grant trademark rights.
Use of those names in fork product names or icons requires permission.
```

GitHub license picker: Apache-2.0. Do not use Creative Commons for the app source.

---

## Liability notes (must appear with the license)

Apache §§7–8 are **AS IS**, no warranty, limitation of damages **except where the law forbids that disclaimer** (or a written contract says otherwise). That is the **code** license. It is **not** a complete shield for the person who ships **MailGent.app**.

Agents must:

- Keep warranty language aligned with Apache (“AS IS”, no fitness for a particular purpose, no promise about data loss).
- **Not** claim “you can never be responsible” or that the license overrides consumer law, especially if the app is **sold**.
- Split hats in user-facing copy:

| Document | Audience |
|---|---|
| `LICENSE` + `NOTICE` | People who copy or fork **source** |
| README / About / short Terms | People who run **our** notarized binary |
| `PRIVACY.md` | What the app does with mail (already in repo) |

- For a mail companion, engineering beats disclaimers: do not rewrite Apple Mail’s on-disk store; mutations go through the user or the provider; fail closed; never silent permanent-delete. Say Time Machine / provider Trash is the user’s backstop, not a restore promise.
- Paid distribution later is a stronger “it should work” duty in many places than a free GitHub download. Do not silently assume the free-OSS disclaimer still fits a store listing.

If adding in-app legal copy, keep it short: Apache-2.0, AS IS, may lose or corrupt mail, official binary only from our Releases/cask, agents the user pairs have their own practices (`PRIVACY.md`).

---

## Homebrew (future — do not ship yet)

**Status: later.** Alpha 0.1.0 is source-only. There is no Developer ID cert, no notarized zip, and no `$99` personal Apple Developer Program on `marotron@gmail.com` yet. Agents must **not** add `Casks/mailgent.rb`, tap docs, or `brew install --cask mailgent` as a working install path. Unsigned/`xcodebuild` zips are not a Homebrew release.

When (and only when) a notarized GitHub Release artifact exists, Homebrew for MailGent is a **cask** (`.app`), never a **formula**.

| Do | Do not |
|---|---|
| Point the cask at **our** notarized GitHub Release (same file as the website/Releases page) | Submit to `homebrew/cask` before a public, hashed artifact exists |
| Fill `version` + `sha256` from that artifact | Check in a cask with a fake sha or `:no_check` “so brew works” |
| `zap` Application Support / preferences for `app.mailgent.MailGent` | Build-from-source in the cask (users install the signed app) |
| Custom tap until the app is public enough for core cask | Call a debug/`xcodebuild` app “the Homebrew build” |

**Later (not now):** cask in this repo (`Casks/mailgent.rb`) and:

```text
brew tap marotron/mailgent https://github.com/marotron/MailGent
brew install --cask mailgent
```

Or a dedicated `homebrew-mailgent` repo later (Homebrew’s default `brew tap marotron/mailgent` shape). Do not create a second GitHub repo unless the user asks.

**After a Release exists**, a cask looks like:

```ruby
cask "mailgent" do
  version "0.x.y"
  sha256 "<digest of the notarized zip or dmg>"

  url "https://github.com/marotron/MailGent/releases/download/v#{version}/MailGent-#{version}.zip"
  name "MailGent"
  desc "macOS companion for Apple Mail with scoped agent access"
  homepage "https://github.com/marotron/MailGent"

  app "MailGent.app"

  zap trash: [
    "~/Library/Application Support/MailGent",
    "~/Library/Preferences/app.mailgent.MailGent.plist",
  ]
end
```

Adjust archive name and `app` path to match the actual Release. `livecheck` against GitHub Releases once versions are tagged.

Signed + notarized + stapled is a **Gatekeeper** requirement for the download, not a liability waiver.

---

## Apple signing identity (never company)

The owner **does not work at company**. MailGent must never be signed, notarized, provisioned, or submitted with:

- Apple ID `employer@example.com`
- Team **Company Developer Team** (`COMPANY_TEAM_ID`)
- Any company certificate, notary profile, or Xcode team

Use the **personal** Apple Developer Program (`marotron@gmail.com`). Ignore other teams on the Mac. Agents must not offer company as a shortcut.

---

## Relicense later

New commits the owner writes can use a different license. Copies **already** published under Apache-2.0 stay Apache-2.0. Outside contributors keep copyright in their lines unless they signed a CLA — relicensing the whole tree then needs every contributor or a rewrite of their code.
