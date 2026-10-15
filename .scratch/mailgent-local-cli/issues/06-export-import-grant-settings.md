# 06 · Export / import grant settings

Type: feature
Status: pending
Blocked by: —
GitHub: https://github.com/marotron/MailGent/issues/36

## Summary

Let users save the current agent grant configuration to a file and load it back later. Useful for backups, moving settings between Macs, and sharing baseline presets across a team.

## Motivation

Grant rules can become complex (mailbox scope, allowed tools, conditions). Users need:

- A backup before making large changes.
- A way to migrate settings to a new Mac or a fresh MailGent install.
- A way to share a known-good baseline (e.g. “read-only assistant” or “draft-only agent”) with others.

## Acceptance

- [ ] **Export** from Grant Desk / Settings produces a human-readable file (preferred: JSON with a stable schema; fallback: `.mailgent-grants` package).
- [ ] Exported file contains grant rules and metadata only — **no credentials, tokens, or pairing secrets**.
- [ ] **Import** reads the same file and previews what will change before applying.
- [ ] Import supports replace or merge for a selected agent.
- [ ] Invalid / unknown tool names or missing mailboxes are surfaced as warnings, not silently skipped.
- [ ] Imported settings are validated against the current app version; unsupported schemas show a clear error.
- [ ] Access Log records import / export events.

## Open questions

- File format: plain JSON, JSON with envelope + checksum, or a signed/encrypted package?
- Should exports be encrypted with the user’s keychain to protect mailbox names / rule details?
- Should there be a shared preset gallery built into the app, or only user-managed files?
- How do we map imported rules when mailbox identifiers differ between source and destination Macs?

## Notes

- Keep secrets out: this is a grant-rules surface only. If a future feature needs credential portability, it must be a separate encrypted escrow flow.
- Related to issue 05 (copy between agents); a saved export can be treated as an anonymous source for the same copy/merge engine.
