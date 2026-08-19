# Research ArchMail and Apple Mail On-Disk Viability

Type: research
Status: resolved

## Question

Can MailGent rely on ArchMail-style filesystem reads of `~/Library/Mail` as a temporary mail source, and detect new mail by polling or watching the store without writing to it?

## Scope

1. **`.emlx` / partial.emlx format** — what fields are reliably available; how attachments are referenced; flag representation; partial vs full download indicators.
2. **Account and mailbox catalog** — how `MailAccountCatalog.swift` maps folders to IMAP paths; multi-account support; which accounts Mail.app has downloaded locally.
3. **Incremental "what's new" detection** — ArchMail is a one-shot scanner; MailGent needs incremental detection. Options: FSEvents, directory mtime polling, `.emlx` filename sequence gaps, envelope index (`Envelope Index` SQLite). Viability and reliability of each.
4. **TCC / sandbox access** — Full Disk Access vs `NSOpenPanel` + security-scoped bookmark; App Sandbox vs Developer ID + notarization tradeoffs for `~/Library/Mail` reads; MAS Guideline 5.2.5 lookalike risk.
5. **Completeness of the local cache** — Apple Mail only holds what it has downloaded. How to detect and surface incomplete/partial messages to the user.
6. **Write / send impossibility** — Confirm writing `.emlx` risks index corruption; confirm copy-paste is the correct outbound path.
7. **Version-break risk** — How stable is the `.emlx` / envelope-index format across macOS versions? Historical breakage evidence.

## Primary sources to consult

- ArchMail source at `/Users/marotron/Dev/ArchMail`: `EmlxReader.swift`, `MboxReader.swift`, `MailAccountCatalog.swift`, `MimeMessageParser.swift`, and any unit tests.
- Apple TCC documentation and Sandbox entitlement references.
- macOS `~/Library/Mail` directory layout (live inspection if needed).
- FSEvents API documentation.

## Out of scope

- Implementing anything in MailGent.
- `mailto:`, AppleScript, MessageUI, or any write path.
- Provider OAuth.

## Answer

**Viable with caveats.** ArchMail-style read-only walks of `~/Library/Mail` can be MailGent’s first-ship mail source. There is no public Apple API for the store.

- **`.emlx`:** byte-count line + RFC822 + trailing plist `flags`. Attachments under `Attachments/<id>/`. Partial is the `.partial.emlx` suffix; never treat as full. Only draft bit `0x10` is proven in ArchMail code.
- **Catalog:** newest `Mail/V*` → UUID account folders; names from `Accounts4.sqlite` or headers. Mailboxes are `.mbox` stems, not IMAP paths. Undownloaded mailboxes are silent gaps.
- **Incremental:** FSEvents on the granted tree while running + on-open sweep keyed by path/mtime/inode. Do not use Envelope Index or filename-sequence gaps. No daemon.
- **Access:** TCC Full Disk Access cannot be skipped by entitlement; NSOpenPanel + security-scoped bookmark is the sandbox extension. MAS sandbox is hostile (no Mail-folder entitlement). Developer ID + notarization + FDA, with bookmark fallback, matches first-ship.
- **Writes:** do not write `.emlx` or Envelope Index; sandbox forbids arbitrary Apple Events. Copy-paste (or a later MailGent ledger) is the outbound path.
- **Break risk:** `.emlx` + newest-`V*` is shippable; Envelope Index is the trap.

Full findings (cited): [../research/archmail-ondisk-viability.md](../research/archmail-ondisk-viability.md)
