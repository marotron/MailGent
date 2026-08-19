# Research: ArchMail and Apple Mail On-Disk Viability

**Question:** Can MailGent rely on ArchMail-style filesystem reads of `~/Library/Mail` as a mail source, and detect new mail by polling or watching the store without writing to it?

**Access date for all citations unless noted:** 2026-08-19  
**Platforms in scope:** macOS (first ship)  
**Out of scope:** Implementing MailGent; OAuth; `mailto:` / AppleScript / MessageUI; writing Apple Mail’s store

---

## 1. Decision-oriented summary

| Topic | Confirmed finding |
| --- | --- |
| Verdict | **Viable with caveats.** ArchMail already reads `~/Library/Mail` as a one-shot import. MailGent can reuse that read path. There is **no public Apple API** to read Mail’s store ([apple-platform-constraints.md](../../mailgent-product-definition/research/apple-platform-constraints.md) §9). |
| `.emlx` | Reliable on-disk unit: first line = decimal MIME byte count, then RFC822 bytes, then a trailing XML plist. ArchMail extracts MIME + optional integer `flags`. Attachments live under sibling `Attachments/<id>/`. Partial vs full is the filename suffix `.partial.emlx` vs `.emlx`. |
| Catalog | `MailAccountCatalog` lists UUID folders under the newest `Mail/V*` directory. Names come from `~/Library/Accounts/Accounts4.sqlite` (`ZACCOUNT`) when readable, else From/To headers. Mailboxes are `.mbox` package stems — **not IMAP paths**. |
| Incremental detect | ArchMail is one-shot. Viable while the app runs: **FSEvents on the granted Mail tree + on-open sweep**, keyed by `(account, mailbox, filename, mtime, inode/size)` — not Envelope Index, not filename-sequence gaps. No always-on daemon required. |
| Access | Two complementary gates: **TCC Full Disk Access** (user grant in System Settings; no entitlement can skip it) and/or **NSOpenPanel + security-scoped bookmark**. MAS **requires App Sandbox**, which has no Mail-folder entitlement. Developer ID + notarization can ship unsandboxed and still needs FDA or a bookmark. |
| Completeness | Local cache is whatever Mail.app has downloaded. Detect partial via `.partial.emlx` (and empty MIME stubs). Never treat partial as complete. |
| Writes | Do not write `.emlx` or Envelope Index. Sandbox forbids sending Apple Events to arbitrary apps. Copy-paste (or a MailGent-owned ledger later) is the only safe outbound in this train. |
| Format-break | `.emlx` layout is long-lived (ArchMail tests target `V10`). Mail migrates into a new `V*` folder on some OS upgrades. Envelope Index schema is undocumented and unused by ArchMail — treat it as a version-break trap. |

---

## 2. `.emlx` / `.partial.emlx` format

ArchMail’s `EmlxReader` is the primary source. Apple does not document this format.

### On-disk layout (proven by parser + tests)

`EmlxReader.parseEmlx` (`ArchMail/Core/EmlxReader.swift`):

1. Read the whole file.
2. First line: UTF-8 decimal **byte count** of the MIME payload.
3. Next `byteCount` bytes: RFC822 / MIME.
4. Remainder: XML plist. ArchMail reads only the `flags` integer (`appleMailFlags(fromTrailing:)`).

Fixture writer in `ArchMailTests/EmlxReaderTests.swift` (`writeEmlx`) emits exactly that shape.

`messageID(from:)` treats the filename stem as Mail’s per-mailbox numeric id: `7.emlx` and `7.partial.emlx` are the same message. `.emlxpart` is skipped.

### Partial vs full

- `isPartialEmlx` = filename suffix `.partial.emlx`.
- `readLabeledMessages` **prefers `.partial.emlx` when both exist** (comment: partial has external attachment stubs). Test: `prefersPartialEmlxOverDuplicatePlainEmlx`.

That preference is an ArchMail import choice. For MailGent **read completeness**, the presence of `.partial.emlx` is the incomplete-download signal. If both files exist, expose `isPartial == true` and still prefer the partial payload for attachment stubs — do not silently upgrade to “complete” because a `.emlx` sibling exists.

### Attachments

`loadExternalAttachments(forEmlx:)` looks for:

- `<parent>/Attachments/<id>/…`
- if parent is `Messages/`, also `<mailbox>/Attachments/<id>/…`

`mergeAttachments` fills empty MIME parts whose filename matches, then appends leftover files. Test `walksMailLibraryAndMergesExternalAttachments` uses a `42.partial.emlx` with an empty `docs.zip` stub plus `Inbox.mbox/Attachments/42/2/docs.zip`.

Body bytes of attachments should be fetched only on demand (product rule); metadata (filename, path, size) is available from the directory listing without loading `Data`.

### Flags

ArchMail documents **one** bit in code:

```swift
/// Apple Mail draft flag (bit 4).
static let draftFlagMask = 0x10
```

`parseEmlxReadsDraftFlagFromPlist` and `readLabeledMessagesPropagatesDraftFlag` prove that bit is stored in the trailing plist. A test comment claims `0x01` is “read”; that is **not** asserted by a named mask and is not an Apple-documented bitfield. MailGent should only ship flag semantics that fixtures prove (plan: read/unread, flagged, draft — only what fixtures prove). Do not invent the rest of the bitfield from folklore.

### Headers and body

`MimeMessageParser.parse` yields From, To, Cc, Subject (RFC2047), Date, HTML/plain body, attachments, `Message-ID`, `In-Reply-To`, `References`. That is the reliable content surface once MIME bytes are in hand.

---

## 3. Account and mailbox catalog

### Version root

`MailAccountCatalog.resolveVersionRoot` (`ArchMail/Core/MailAccountCatalog.swift`):

- If the given URL is already a `V<digits>` folder, use it.
- Else list `Mail/V*`, pick the **highest version number**.

Tests (`MailAccountCatalogTests`) always build a `V10` tree. ArchMail UI copy mentions `V10` by name (`ContentView.openMailLibraryPanelForPicker`).

Implication: MailGent should follow “newest `V*`”, not hard-code `V10`.

### Accounts

Account folders are UUID directory names (`8-4-4-4-12` hex) that contain mailbox content (`.mbox`, `.emlx` / `.partial.emlx`, `Messages`, or `table_of_contents`). Empty UUID dirs are ignored.

Display name / username:

1. `~/Library/Accounts/Accounts4.sqlite` then `Accounts3.sqlite`, table `ZACCOUNT` columns `ZIDENTIFIER`, `ZACCOUNTDESCRIPTION`, `ZUSERNAME` (read-only `sqlite3_open_v2`).
2. Else infer from Sent `From:` / Inbox `Delivered-To` / `To` headers.
3. Else short-id fallback.

`Accounts4.sqlite` is a **second TCC-sensitive path** (ArchMail error copy: grant FDA “to ArchMail (and Accounts names)”). If the Accounts DB is blocked, identity still works via header inference.

This is **not** an IMAP path map. There is no IMAP URL, UIDVALIDITY, or server mailbox encoding in the catalog. Mailboxes are local `.mbox` package names (`INBOX.mbox` → display `Inbox` via `MboxReader.displayMailboxName`). Nested packages under companion subfolders get a relative display path.

Multi-account: one UUID folder per Mail.app account that has local mailbox content. Accounts Mail.app has not downloaded locally simply do not appear.

`folderStats` counts `.emlx` / `.partial.emlx`, `.mbox` dirs, bytes, newest mtime. `table_of_contents` alone still counts as a mailbox (empty-but-present).

---

## 4. Incremental “what’s new” detection

ArchMail is a one-shot walker (`readLabeledMessages`). MailGent needs incremental detection **without writing the store**.

| Option | Viability | Notes |
| --- | --- | --- |
| **FSEvents on granted Mail tree** | **Primary while app is running** | Apple’s FSEvents programming guide: `FSEventStreamCreate` on a path, schedule on a run loop, `FSEventStreamStart`. Events are **directory-level** unless file-events flags are used; coalescing may set `kFSEventStreamEventFlagMustScanSubDirs` → rescan that subtree. Dropped-event flags → **full rescan**. Latency (example in the guide: 3s) coalesces bursts. An event id (`sinceWhen` / `FSEventStreamGetLatestEventId`) can resume history after relaunch **if MailGent persists it** — that is not a background daemon. The live stream still dies with the process. |
| **On-open / on-foreground sweep** | **Required complement** | Catches mail that arrived while MailGent was quit (and any dropped FSEvents). Cheap: compare file identity to last ingest. |
| **Directory / file mtime + inode + size** | **Identity key + coarse fallback** | Skip re-parse when the same `(path, inode, mtime, size)` was ingested. New `.emlx` or changed mtime → parse. `MailAccountCatalog.folderStats` already reads `contentModificationDateKey`. Directory mtime does not see nested `Attachments/` changes; FSEvents + identity key cover that. |
| **`.emlx` filename sequence gaps** | **Not reliable** | Filenames are per-mailbox integers, but deletions, compact, and partial/full pairs create gaps. A missing number is not “new mail.” |
| **Envelope Index SQLite** | **Do not use for v1** | ArchMail never opens it. Schema is undocumented; Mail.app owns it. Reading it couples MailGent to a private index that historically moves with `V*` migrations. Writing it is corruption. Incremental detect does not need it if the filesystem walk + identity key works. |

Recommended default (matches the first-ship plan): **FSEvents + on-open sweep; no always-on helper.** Persist last-seen identities in MailGent’s own SQLite, not in Mail’s tree.

FSEvents still needs the same access grant as reads (FDA or security-scoped URL to the Mail folder). Watching a path you cannot read is useless.

Source: [Using the File System Events API](https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html) (Apple Documentation Archive).

---

## 5. TCC / sandbox access

Two independent gates stack.

### 5.1 Full Disk Access (TCC)

Apple: *“Your app can’t automatically gain full disk access through an entitlement or with code: the person using your app must choose to grant access in System Settings > Privacy & Security.”* ([Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox))

`com.apple.security.files.all` (“All files entitlement”) exists and is **deprecated** in Apple’s current entitlements index. It is not a substitute for the System Settings grant.

This session: `ls ~/Library/Mail` from a sandboxed agent returned **`Operation not permitted`** — evidence the path is TCC-protected even before MailGent exists.

ArchMail’s own copy assumes this: `MailAccountCatalogError.unreadable` → “Grant Full Disk Access to ArchMail in System Settings.” Picker hint: “grant Full Disk Access if macOS blocks it.”

Files & Folders in System Settings is a **different**, narrower TCC category (Desktop / Documents / Downloads) ([Control access to files and folders on Mac](https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac)). `~/Library/Mail` is not that list; it is Full Disk Access (or a user-selected bookmark).

### 5.2 App Sandbox + user-selected files + bookmarks

MAS **requires** App Sandbox ([App Sandbox](https://developer.apple.com/documentation/security/app-sandbox); [App Sandbox Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox)).

There is **no** Mail-library sandbox entitlement. Standard folder entitlements cover Music / Movies / Pictures / Downloads, not `~/Library/Mail`.

Documented extension of the sandbox:

- `com.apple.security.files.user-selected.read-only` / `.read-write` — Open/Save dialog ([user-selected.read-only](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-only)).
- Selecting a **folder** recursively includes nested items ([Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox)).
- Persist with a **security-scoped bookmark**; on later launch, resolve + `startAccessingSecurityScopedResource` / `stopAccessingSecurityScopedResource`.

ArchMail is sandboxed (`ArchMail.entitlements`: `app-sandbox`, `files.user-selected.read-write`, `network.client`). It opens `NSOpenPanel` on `~/Library/Mail`, calls `startAccessingSecurityScopedResource()`, and persists account pins with `URL.bookmarkData` + `.withSecurityScope` (`SavedMailAccountsStore.swift`).

MailGent first-ship should use **read-only** user-selected entitlement if sandboxed. ArchMail’s read-write is for its archive-export product, not a license to write Mail.

Sandbox also **forbids sending Apple Events to arbitrary apps** ([Protecting user data with App Sandbox](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox)) — another reason AppleScript-to-Mail is out.

Mandatory access controls still apply *after* sandbox extension: POSIX, ACLs, SIP, TCC. User-selected `~/Library/Mail` can still fail without FDA. ArchMail handles that by asking for both.

### 5.3 Developer ID + notarization vs MAS

| Path | Sandbox | Mail read |
| --- | --- | --- |
| Mac App Store | Mandatory | Hostile: no Mail entitlement; Open Panel + bookmark is the only documented sandbox extension; Review still has 5.2.5 lookalike + 5.1.2 data-sharing. |
| Developer ID + notarization | Optional; Hardened Runtime required for notarization | Can ship unsandboxed; **still** needs FDA or a bookmark. Early distribution without Gmail/Yahoo OAuth caps. |

Notarization ≠ App Review ([Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution); prior research §8.1).

First-ship working assumption (product plan): **Developer ID + notarization + FDA (or security-scoped Mail folder)**. Keep Open Panel as a fallback onboarding path, as ArchMail does.

### 5.4 Guideline 5.2.5

App Store Review Guidelines **5.2.5**: *“Don’t create an app that appears confusingly similar to an existing Apple product, interface (e.g. Finder), app (such as the App Store, iTunes Store, or Messages)…”* ([Guidelines](https://developer.apple.com/app-store/review/guidelines/), accessed 2026-08-19; last updated June 8, 2026). Mail is in the same “existing Apple product” class even though the sentence’s examples list Messages, not Mail. Prior platform research already flagged this. Control-first companion IA (not a Mail.app clone) is the product mitigation — independent of distribution channel.

---

## 6. Completeness of the local cache

Apple Mail only stores what it has downloaded. There is no first-party completeness API.

Detect incomplete messages from the filesystem:

| Signal | Meaning |
| --- | --- |
| Filename `.partial.emlx` | Partial download. Surface `isPartial`. Searchable, never silently “full.” |
| Empty MIME attachment parts + files under `Attachments/<id>/` | Body stubs; bytes on disk separately. |
| Empty MIME attachment parts and **no** external file | Attachment not downloaded. `not_available` for bytes. |
| Account UUID folder missing / no `.mbox` | Mail.app has not materialized that account locally. Omit it. |
| Mailbox Mail.app is set not to store locally | Absent from the tree. There is **no** on-disk signal that it exists on the server. Silent gap — product must say “local cache only.” |
| `table_of_contents` without `.emlx` | Empty mailbox present. |

Do not consult Envelope Index to decide completeness for v1.

Live `~/Library/Mail` layout was **not** inspected this session (TCC `Operation not permitted`). That itself confirms the access model. Do not copy live mail into the repo or CI.

---

## 7. Write / send impossibility

- **No public write API** for Apple Mail’s store. MailKit customizes Mail.app from inside; it does not grant a third-party process write access to `~/Library/Mail` (prior research §9).
- Writing `.emlx` (or `Attachments/`, `table_of_contents`, Envelope Index) would fight Mail.app’s indexer. Undocumented; corruption / duplicate / lost-flag risk. ArchMail never writes the Mail tree; it reads and copies **out**.
- Sandbox: Apple Events to arbitrary apps are forbidden. AppleScript-to-Mail is incompatible with MAS sandbox and is out of this train anyway.
- `mailto:` / MessageUI are compose-handoff, not store writes; YAGNI until a later outbound decision.

Copy-paste into Mail.app (or a MailGent-owned draft ledger that still does not write Mail) is the only outbound path this research supports.

---

## 8. Version-break risk

| Surface | Stability | Evidence |
| --- | --- | --- |
| `.emlx` (byte count + MIME + trailing plist) | **High enough to ship against** | ArchMail parser + tests; format has been the Mail.app on-disk unit for many OS releases. Trailing plist keys beyond `flags` are unread — extra keys are tolerated. |
| `Mail/V*` directory | **Expect renumbering** | Catalog already selects newest `V*`. Tests use `V10`. UI copy still says “V10” as an example, not a contract. |
| `.mbox` packages + `Messages/` + `Attachments/<id>/` | **Stable in ArchMail’s model** | Walkers keyed off those names. |
| `Accounts4.sqlite` / `ZACCOUNT` | **Core Data — can shift** | Fallback to header inference already exists. |
| Envelope Index | **Fragile; unused** | Not in ArchMail. Highest break risk if MailGent coupled to it. |

Historical breakage: this research did not find Apple release notes documenting `.emlx` changes (Apple does not publish the format). The practical mitigation is **fixture tests + newest-`V*` resolution**, not Envelope Index.

---

## 9. Implications for MailGent

1. **Read path is viable.** Adapt `EmlxReader`, `MailAccountCatalog`, `MimeMessageParser` (and their tests/fixtures) into a MailGent `MailStore` target. Do not submodule ArchMail. Do not use `MboxReader` for the live Mail library (that path is export/import of classic mbox); live mail is `.emlx` trees inside `.mbox` packages.
2. **Access onboarding:** fail closed. Prompt Full Disk Access **and** offer “Choose Mail folder” (bookmark). ArchMail already proves both. Prefer **read-only** sandbox entitlements if sandbox is on.
3. **Distribution:** MAS sandbox is hostile to this source. Developer ID + notarization matches the first-ship assumption and also avoids Gmail/Yahoo OAuth caps.
4. **Incremental:** FSEvents on the granted root while running + identity-keyed ingest + on-open sweep. No helper daemon. No Envelope Index.
5. **Partial mail:** first-class `isPartial`; missing body/bytes → `not_available`. Never treat partial as full.
6. **Flags:** only draft (`0x10`) is proven in ArchMail code. Add read/flagged only with fixture literals.
7. **Outbound:** no Mail-store writes, no AppleScript. Copy-paste vs a MailGent draft ledger is a later product question, not a filesystem question.
8. **5.2.5:** keep the companion visually/structurally distinct from Mail.app regardless of store source.
9. **CI:** synthetic + anonymized `.emlx` trees only. Never live `~/Library/Mail`.

---

## 10. Gaps

| Gap | Why it remains open |
| --- | --- |
| Live `~/Library/Mail` layout on this machine | TCC blocked listing (`Operation not permitted`). Confirm `V*` number, Envelope Index filename, and `.partial.emlx` ratio on a machine with FDA during Stage 1 manual test — do not check that into git. |
| Apple bitfield for `flags` other than draft `0x10` | Not in Apple docs; not a named ArchMail mask. Prove in MailGent fixtures before exposing. |
| Whether user-selected bookmark **alone** (no FDA) always reads Mail on current macOS | ArchMail treats FDA as the fallback when the panel is not enough. Stage 1 onboarding should handle both failure modes. |
| FSEvents `FileEvents` flag vs directory-level rescan | Guide’s default is directory paths + possible `MustScanSubDirs`. Either is fine for “something changed under Mail”; identity-keyed ingest does the rest. |
| Exact Envelope Index path/schema | Intentionally unread. |

---

## 11. Source index

| Source | URL or path | Accessed |
| --- | --- | --- |
| `EmlxReader.swift` | `/Users/marotron/Dev/ArchMail/ArchMail/Core/EmlxReader.swift` | 2026-08-19 |
| `MailAccountCatalog.swift` | `/Users/marotron/Dev/ArchMail/ArchMail/Core/MailAccountCatalog.swift` | 2026-08-19 |
| `MimeMessageParser.swift` | `/Users/marotron/Dev/ArchMail/ArchMail/Core/MimeMessageParser.swift` | 2026-08-19 |
| `MboxReader.swift` | `/Users/marotron/Dev/ArchMail/ArchMail/Core/MboxReader.swift` | 2026-08-19 |
| `SavedMailAccountsStore.swift` | `/Users/marotron/Dev/ArchMail/ArchMail/Core/SavedMailAccountsStore.swift` | 2026-08-19 |
| `ContentView.swift` (Open Panel / FDA copy) | `/Users/marotron/Dev/ArchMail/ArchMail/ContentView.swift` | 2026-08-19 |
| `ArchMail.entitlements` | `/Users/marotron/Dev/ArchMail/ArchMail/ArchMail.entitlements` | 2026-08-19 |
| `EmlxReaderTests.swift` | `/Users/marotron/Dev/ArchMail/ArchMailTests/EmlxReaderTests.swift` | 2026-08-19 |
| `MailAccountCatalogTests.swift` | `/Users/marotron/Dev/ArchMail/ArchMailTests/MailAccountCatalogTests.swift` | 2026-08-19 |
| App Sandbox | https://developer.apple.com/documentation/security/app-sandbox | 2026-08-19 |
| App Sandbox entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox | 2026-08-19 |
| Accessing files from the macOS App Sandbox | https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox | 2026-08-19 |
| Protecting user data with App Sandbox | https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox | 2026-08-19 |
| user-selected.read-only | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-only | 2026-08-19 |
| user-selected.read-write | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write | 2026-08-19 |
| files.all (deprecated) | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.all | 2026-08-19 |
| Using the File System Events API | https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html | 2026-08-19 |
| Control access to files and folders on Mac | https://support.apple.com/guide/mac-help/control-access-to-files-and-folders-on-mac-mchld5a35146/mac | 2026-08-19 |
| App Store Review Guidelines | https://developer.apple.com/app-store/review/guidelines/ | 2026-08-19 |
| Notarizing macOS software | https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution | 2026-08-19 |
| Prior: Apple platform constraints | [apple-platform-constraints.md](../../mailgent-product-definition/research/apple-platform-constraints.md) | 2026-08-15 |
| Live `ls ~/Library/Mail` | this machine, sandboxed shell | 2026-08-19 (`Operation not permitted`) |
