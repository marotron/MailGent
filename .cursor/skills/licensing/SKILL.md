---
name: licensing
description: >-
  Chooses and applies MailGent’s source license (Apache-2.0 + NOTICE),
  trademark reservation, user-facing liability notes, and Homebrew cask
  distribution. Use when adding LICENSE, NOTICE, terms, warranty or
  data-loss disclaimers, choosing MIT vs Apache vs GPL, or adding
  Homebrew / brew cask / tap / GitHub Releases install docs.
---

# MailGent licensing

Follow [docs/agents/licensing.md](../../../docs/agents/licensing.md). Do not re-open the license choice.

## Hard rules

1. **License is Apache-2.0** plus a root `NOTICE`. Not MIT, not GPL/AGPL, not Creative Commons for app source.
2. **Closed forks may use the code** if they keep copyright, license, and NOTICE credits. That is the point of Apache here.
3. **Name and icon are not licensed.** Forks rename. Apache does not grant the MailGent trademark.
4. **Apache AS IS is not “no responsibility ever.”** Put a short user disclaimer on official binaries; do not claim the license beats consumer law or a paid store listing.
5. **Homebrew is future.** Do not add a cask or tap until a notarized GitHub Release zip exists. Then it is a cask of that file only. No fake `sha256`. No formula. No `homebrew/cask` PR until that artifact exists.
6. **Never sign or notarize under an employer/company team.** Personal Apple ID only (`marotron@gmail.com`). Ignore paid company teams on the Mac.

## Apply (only when the user wants files)

1. Ask for copyright holder + year if unknown.
2. Write official Apache-2.0 text to `LICENSE` (do not paraphrase).
3. Write `NOTICE` from the template in `docs/agents/licensing.md`.
4. README: SPDX, NOTICE, trademark sentence, official binary = Releases (+ cask when live).
5. Liability: AS IS, possible mail loss, we do not rewrite Apple Mail’s store, paired agents have their own practices — see `PRIVACY.md`.
6. Homebrew: **not now.** Add `Casks/mailgent.rb` only after a real notarized Release URL and sha256; then tap instructions in README.

## Do not

- Relicense without an explicit user change to this policy.
- Invent a CLA, EULA novel, or patent filing.
- Tell the user a license protects the *idea*.
- Use an employer/company Apple ID or Developer Program team for codesign, notary, App Store, CI, or Xcode team selection.
