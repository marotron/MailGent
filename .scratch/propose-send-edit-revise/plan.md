# Plan: Edit + revise + refer in the propose_send confirm window

**Status:** Plan only. Experimental feature. Nothing implemented. No version bump, no CHANGELOG entry until it ships.

**Source of truth for visuals:** [prototype.html](prototype.html) — approved tweaks are listed in section 3 and must be matched in SwiftUI, not redesigned.
**Source of truth for mechanism:** [vision.md](vision.md) — protocol, secret rules, slices. This plan does not restate it; it points at it.

## Why experimental

The confirm window is the last human checkpoint before mail leaves the machine, and this feature adds an editable surface, a new agent round-trip, and new payload fields. It ships behind a flag, stays off by default, and is expected to be tweaked for a while before it is the default. The flag is the escape hatch while the tweaks settle.

---

## 1. Stack pin

From `project.yml`: Swift 6.0, macOS deployment target **14.0**.

- SwiftUI `TextEditor` cannot do atomic inline pills, so the body editor is an `NSViewRepresentable` over `NSTextView` with `NSTextAttachment` for secret tokens. Verify the attachment and selection APIs against apple-doc-mcp before writing the editor.
- No deployment bump. If an API needs macOS 15+, call it out and pick the 14.0 alternative.

## 2. Feature flag

- `UserDefaults` key `experimentalProposeSendEdit` (name to confirm), default **off**.
- Off → today's confirm window, byte for byte. On → the prototype's window.
- Flag lives in Settings under an "Experimental" section, with one line of copy: editable draft, ask the agent to revise, pin passages for the agent's attention.
- All new code paths are gated at the window's entry point, so the flag-off path shares no state with the new one.

## 3. Approved visual tweaks (match these exactly)

All in the main pane of the existing 820×640 context window. Left rail stays `SendProposalContextThreadView` as it is today.

### 3.1 Referred passage highlight (`mark.ref`)

- Violet tint `#efe8ff`, text `#4a2aa0`, `padding: 1px 5px`, `margin: 0 1px`, **`border-radius: 0`**, no bold, no underline. `display: inline-block` so the number chip can sit against it. (Known trade-off: a long passage becomes one box instead of flowing with the wrapping prose.)
- Secret tokens inside a highlight keep the orange `.tok` pill (`#ffd9a3` / `#6b3a00`, `border-radius: 4px`, not bold).

### 3.2 Number chip (`.refno`) — the most iterated element

- A 14px circle, sibling **after** the highlight, never inside it and never part of the body text.
- Position: overlaps the highlight's top-right corner — `margin-left: -5px`, raised `vertical-align: 11px`.
- **Resting state:** transparent background, purple number, no border.
- **Hover** (over the highlight or the chip): fills violet with a white number and scales to **1.45×**, animated 0.12s on transform, background, and color.
- The number matches the row number in the references strip.

### 3.3 References strip

- Above the body, light violet band `#faf8ff`. Header: `Passages for Cursor's attention · N · sent on Ask to look, Ask to revise, or Send`.
- Each row: number chip, quoted passage, note input (`What should Cursor look at here?`), remove button.
- **Secret in a quote:** the value is replaced by an orange masked pill `🔒 <token name>` with a tooltip ("Secret constant — its value is not revealed to the agent"), plus an amber badge `🔒 redacted for agent` on the row. The literal value never appears in the strip.
- **Note presets:** focusing the note input expands a plain list **below the row** (pushes content down, not a floating dropdown), indented by the chip column (26px), full remaining width, no box or background. Caption "Common instructions" when the field is empty, "Suggestions" while typing.
- **Fuzzy filtering:** subsequence match, scoring up consecutive hits and word-start hits (`fuzzyScore` in the prototype). Typing `shrter` finds "Make this shorter". No match shows "No matching preset — keep typing, your text is sent as-is."
- Preset list (`NOTE_PRESETS`):
  - Check this is accurate and up to date
  - This is a guess — verify before sending
  - Check tone is right for the recipient
  - Make this shorter
  - Rewrite more formally
  - Check dates and times against my calendar
- Clicking a preset fills the note and collapses the list. Escape or blur collapses it.

### 3.4 Referring a selection — three equivalent paths

All call the same `referPassage` with the selection mapped back to tokens:

1. **Selection bubble** — after mouseup on a non-empty body selection (review mode), a violet pill floats centered above the selection (flips below near the top edge): `Refer to agent's attention` with a `⌘⇧A` keycap.
2. **Right-click menu** — first item `Refer to agent's attention` with `⌘⇧A` right-aligned, then the existing rewrite items.
3. **Keyboard** — `⌘⇧A` with a body selection. No selection → no-op, so it never fires while typing in a field.

### 3.5 Status strip

- `border-bottom` removed. The "Draft v1 · Cursor" chip and the "Secret constants replaced for send" notice sit on the plain background.

### 3.6 Unchanged from the existing app (do not reinvent)

- Window size 820×640 with context, 560×620 without.
- Left rail: thin 124px / full 260px, avatars on the ownership side, sharp corner on that side, private rows on a darker band, draft card last and yellow.
- `handedOff` phase banner: green check, "Handed to Apple Mail", "Mail accepted the send. It may take a moment to appear in Sent."

## 4. Mechanism (what the tweaks depend on)

Full protocol is in vision.md §4. The parts the tweaks rely on:

- **Tokenized source of truth.** The body is stored as `[[mg:name]]` tokens. The human sees resolved values; every agent-facing string (diffs, quotes, notes, `currentBody`, `sentBody`) is tokenized and then redacted. A selection that includes a pill maps back to the whole token via `displayToTokens` before anything else happens.
- **Pins store quotes, not offsets.** A pin is re-found in the current body; if the passage is gone it is sent `stale: true` and struck through.
- **References ride along.** Pins are attached to whichever reply happens next: `send`, `revise_requested`, or `attention_requested` ("Ask agent to look", pins only, no rewrite).
- **Redaction is two passes.** Capture tokenizes allowlisted literals; the payload builder redacts anything still literal. Reference 5 in the prototype ("…is +1 555 0142 if…") must reach the agent as `[[mg:phone_mobile]]`.

## 5. Slices

Each slice is a vertical cut, flag-gated, and dogfoodable on its own. Tests are proposed per slice and **written only after you confirm the seams** (per `/tdd`).

| # | Slice | Ships | Tests (MailStore, pure) |
|---|---|---|---|
| 1 | Edit + Send edited | Editable To/Cc/Bcc/subject/body, token pills, diff, recipient "added" callouts, HTML→plain notice, `send` gains `edited` / `changes` / `sentBody` | word-level diff hunks, recipient diff, literal→token (body only), redaction of envelope literals |
| 2 | Refer to attention | Selection bubble, ⌘⇧A, right-click item, references strip with secret pills + badge, fuzzy note presets, `attention_requested` outcome, references attached to `send` | selection→token snapping, quote redaction, stale pin detection, fuzzy ranking |
| 3 | Ask to revise | Popover, presets, note, `revise_requested` + compiled `instructionText`, window stays open in "waiting" | instruction compiler, preset + note + userEdits assembly |
| 4 | Agent loop | `propose_send.revises`, in-place v2 swap, revision cap, tool description update | state transitions, cap, proposalId validation |

Slice 2 before slice 3 because the selection plumbing is what you have been tuning, and refer needs no agent round-trip to be useful.

## 6. Gates

- **YAGNI** — no payload preview panel in the product (it stays a prototype aid), no source-less context cards, no new token types. The fuzzy matcher is the prototype's ~15 lines, not a search library.
- **KISS** — one `NSTextView` wrapper, one references model, one payload builder shared by all three outcomes.
- **DRY** — the three refer paths call one function; redaction lives in one pass used by every outbound string.
- **SOLID** — the editor knows nothing about MCP; the payload builder knows nothing about views.

## 7. Risks

- **`NSTextView` attachment editing** is the hardest piece: atomic pills, selection snapping across a pill, and read-back to tokens. Spike this before building slice 1's UI.
- **`⌘⇧A` collisions** — confirm it is free in the confirm window; it must not be stolen from a focused text field (the prototype guards on "selection is inside the body").
- **Tool description changes** do not refresh a running Cursor session (mcp-tool-catalog-restart rule). Slice 4 needs a relaunch note, not a code workaround.
- **Flag drift** — experimental code tends to rot. Each slice lands with its tests so the flag-on path stays green.

## 8. Open questions

1. **Flag placement** — Settings → Experimental section, or a hidden default for now?
2. **Note preset list** — the six in §3.3 are my picks for the prototype. Keep, cut, or add?
3. **Fuzzy scope** — note field only (as built), or also the revise popover's note?
4. **`⌘⇧A`** — happy with that combo, or do you want a different one?
5. **Slice order** — refer (slice 2) before revise (slice 3), as proposed?
6. **Text-only context cards** — still open from vision.md question 10: keep the mail/vault source requirement, or allow a source-less summary card?
7. **Revision cap and expiry** — still open from vision.md questions 3 and 4 (proposed: cap 5, keep the original deadline).
