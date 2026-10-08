# UI element inventory

Living catalogue of reusable UI element **types** and **placement rules** so Access Log, Companion, Grant Desk, and throwaway HTML prototypes stay uniform.

**Rule:** before inventing a new control, find the matching type here (or add a type first). Prototypes under `.scratch/**/examples/` must use the same names and placement.

**Swift sources of truth** live next to the type. HTML protos mirror chrome only.

---

## Principles

1. **One job per control** — label names the object acted on (`Preview` = this file; `Open in Apple Mail` = this message).
2. **Same chrome for the same job** — bordered secondary actions share one visual recipe (icon-only; expand to icon + label on hover).
3. **Placement follows object, not screen** — actions that act *on* the visible entity trail inside its card; actions that open a *related* surface sit in the handoff row directly under that card.
4. **Fail closed copy** — missing handoff data shows a caption under the button; do not fake success.

---

## Element types

### `SecondaryAction`

| Field | Value |
|---|---|
| **Job** | Non-destructive handoff / open / preview |
| **Chrome** | Height-locked to Access Log `Formatted` (small segmented metrics); track + raised face; icon-only by default |
| **Hover** | Expands to icon + regular-weight small-control label; border/icon → accent blue |
| **Always expanded** | `alwaysExpanded: true` keeps icon + label (Ask dialog message actions) |
| **Swift** | `SecondaryActionButton` in `CompanionBits.swift` |
| **HTML** | `.secondary-action` (+ optional `.secondary-action-row`) |
| **Icons** | Always shown; label appears on hover / focus; see [Action catalogue](#action-catalogue) |

**Do not** invent a one-off bordered button (`.preview-btn`, `.open-in-mail`, …). Use this type.

### `SecondaryActionRow`

| Field | Value |
|---|---|
| **Job** | Host related / parent handoffs under an entity card |
| **Chrome** | `VStack` / column, leading-aligned, 6–8px gap above first button, 6px between button and fail-closed note |
| **Swift** | Wrapper around `SecondaryActionButton` (e.g. `OpenInMailButton`) |
| **HTML** | `.secondary-action-row` |

### `EntityTrailingAction`

| Field | Value |
|---|---|
| **Job** | Acts on the entity shown in the card (max **one**) |
| **Placement** | Trailing, vertically centered inside the entity card |
| **Chrome** | Same as `SecondaryAction` |
| **Example** | Preview on Access Log / attach **file card** |

### `FileCard`

| Field | Value |
|---|---|
| **Job** | Delivered attachment result (`get_attachment`) |
| **States** | `granted` / `denied` / `missing` / `huge` (hatch + status icon when not granted) |
| **Trailing** | `Preview` always — same clickable chrome for all states; denied / missing / huge fail-closed on click (reason under card), not dimmed |
| **For-row** | Plain “for [subject]” (not a link) · parent message handoff trails right — **not** “open the attachment in Mail” |
| **Swift** | `FileCard` in `CompanionBits.swift`; Companion Read uses `MessageAttachmentRow` |
| **HTML** | `.file-card` in `prototype-access-log-attach.html` |

### `MessageAccessCard`

| Field | Value |
|---|---|
| **Job** | Truth-first message shell (headers, body, attachment info/content) |
| **Tap** | None — Preview button only opens Companion Read / attachment preview |
| **Chip row** | Source chip left · Preview + `Open in Apple Mail` trailing right |
| **Attachment Content** | When bytes were not in the agent response → `FileCard` missing/denied chrome (name + state line). No nested Preview (chip-row owns it) |
| **Swift** | `MessageAccessCard` |
| **HTML** | `.msg-card` |

### `SearchResultCard`

| Field | Value |
|---|---|
| **Job** | One search/list hit as returned to the agent (`items[]`) |
| **Fields only** | `subject`, `from`, `date`, `id`, `placement`, `isPartial`, `accountID` — never to/cc/body/attachments |
| **Chrome** | Same card border as message card; placement (+ partial) chips; labeled lines |
| **Chip row** | Chips left · Preview (message → Companion Read) + `Open in Apple Mail` trailing right on the same row |
| **Tap** | None — body is not clickable; Preview button only |
| **Swift** | `SearchResultCard` in `CompanionBits.swift` |
| **HTML** | `.search-card` in `prototype-access-log-attach.html` |

### `CollapsibleAuditMessage`

| Field | Value |
|---|---|
| **Job** | Expand/collapse Access Log message row (multi-hit lists) |
| **Not for** | Single `get` Formatted Response — show `MessageAccessCard` flat (no chevron) |
| **Swift** | `CollapsibleAuditMessage` |
| **HTML** | `.collapsible` (unused for get in proto) |

### `KindChrome` / list chrome

| Field | Value |
|---|---|
| **Job** | Label the response kind (Message / Attachment / Message list) |
| **Chrome** | Icon + semibold callout |
| **Swift** | Inline in Access Log pretty response |
| **HTML** | `.kind-chrome`, `.msg-list-chrome` |

### `GrantFieldBadge` / `RuleFieldMarkChip` / hatch

Documented in code (`GrantFieldBadgeRow`, `RuleFieldMarkChip`, `HatchDeniedStyle`). Do not restyle in protos without updating Swift.

---

## Action catalogue

| Action ID | Label | Icon (SF Symbol) | Placement | When |
|---|---|---|---|---|
| `previewFile` | Preview | `eye` | Entity trailing on `FileCard` (`get_attachment`) | Always on file card with full chrome; granted runs preview; denied / missing / huge fail-closed explain on click |
| `previewMessage` | Preview | `eye` | Trailing right on `MessageAccessCard` / `SearchResultCard` chip-row | Message focus (`get`, search/list) — opens Companion Read (re-fetch). Not file bytes |
| `openMessageInMail` | Open in Apple Mail | `OpenInMailGlyph` (`arrow.up.right.square`) | Trailing right on message/search chip-row (Companion Read: under body) | Message in focus (`get`, search card, Companion Read) |
| `openParentMessageInMail` | Open message in Apple Mail | `OpenInMailGlyph` (`arrow.up.right.square`) | Trailing right on `attach-for` (“for [subject]”) | Attachment in focus (`get_attachment`) — opens **parent email**, not the file |
| `openAttachmentSystem` | (row / Preview) | `paperclip` / `eye` | Companion Read attachment row; Access Log Preview | Re-export bytes → `NSWorkspace.open` / Quick Look |

### Attachment entry — decided solution

**Both**, with split roles (do not use a single “Open in Apple Mail” as the only affordance on an attach row):

1. **Preview** (trailing on file card) — re-export from mailbox → system viewer / Quick Look. This is the accurate action for the file the agent received.
2. **Open message in Apple Mail** (trailing on `attach-for` / “for [subject]”) — `message://` handoff for the parent RFC Message-ID. Label includes **message** so it is not read as “open this PDF in Mail”.

Avoid opening the attachment *inside* Apple Mail as a primary path: Mail is the mailbox surface; the system viewer is the file surface. Companion Read already follows that split.

---

## Placement map (Access Log)

```
get
  KindChrome "Message"
  meta + grant field badges
  MessageAccessCard            ← truth: fields/body/names agent got (no collapsible)
    chip-row: [account · placement]   [Preview] [Open in Apple Mail]
                                      ↑ trailing right; Preview = Companion Read (message)

search / list
  KindChrome "Message list · N" (+ more if nextCursor)
  headers-only note
  for each agent item → SearchResultCard   ← only item fields (subject/from/date/id/placement/isPartial)
    chip-row: [placement] [partial?]     [Preview] [Open in Apple Mail]
                                         ↑ trailing right; Preview = Companion Read (message)

get_attachment
  KindChrome "Attachment"
  attach-for: for [subject]              [Open message in Apple Mail]
                                         ↑ trailing right (parent message)
  FileCard                     ← truth: file delivery result to the agent
    [meta…]          [Preview] ← EntityTrailingAction; always full chrome; fail-closed when not granted
```

**Rule:** Formatted Response never invents body/file bytes the agent did not receive. Preview / Open in Apple Mail are Access Log affordances on top of that truth (search Preview re-fetches the message for you; it does not claim the agent received the body).

Companion Read:

```
Message body
MessageAttachmentRow           ← openAttachmentSystem (row tap)
SecondaryActionRow
  openMessageInMail
```

---

## Change log (inventory)

| Date | Change |
|---|---|
| 2026-10-04 | Access Log `get` chip-row Preview opens Companion Read (same as search); file Preview stays on `get_attachment` FileCard. |
| 2026-10-04 | Open in Apple Mail icon → `OpenInMailGlyph` (`arrow.up.right.square` external-link). |
| 2026-10-04 | Access Log mode chrome: only the active view (Formatted or JSON Pretty/Raw) shows raised selected face. |
| 2026-10-04 | `SecondaryAction` is icon-only; hover/focus expands to icon + label. |
| 2026-10-04 | Message/search card body is not clickable; Preview button only opens Companion Read. FileCard missing status icon uses solid border. |
| 2026-10-03 | `SecondaryAction` chrome = Formatted segment (track + raised face). |
| 2026-10-03 | Swift: `FileCard` + `SearchResultCard` + Access Log Formatted / JSON Pretty|Raw mode chrome. |
| 2026-10-03 | get Attachment Content uses FileCard missing/denied chrome (not teal “Not included” tile). |
| 2026-10-03 | Attach Preview keeps full SecondaryAction chrome for denied / missing / huge (fail-closed on click, not dimmed). |
| 2026-10-03 | Attach blocked Preview stays clickable (pointer + hover); reason shows under file card. |
| 2026-10-03 | Attach `attach-for` subject is plain text (no Companion Read link); Open message in Apple Mail remains. |
| 2026-10-03 | get Formatted drops collapsible — flat MessageAccessCard + meta/badges. |
| 2026-10-03 | Attach file-card Preview always shown; blocked + explain for Not granted / Not available / Too large. |
| 2026-10-03 | Search Preview enabled as `previewMessage` → Companion Read (not blocked for missing file bytes). |
| 2026-10-03 | Attach: Open message in Apple Mail trails on `attach-for` row; search actions on chip-row. |
| 2026-10-03 | Search Formatted = list of `SearchResultCard` from agent `items` only (no full-message shell). |
| 2026-10-03 | get/search also carry Preview + Open in Apple Mail; file Preview blocked when response had no file bytes. Truth-first Formatted Response rule. |
| 2026-10-03 | Initial inventory. Unified `SecondaryAction`. Attachment = Preview + Open message in Apple Mail. |
