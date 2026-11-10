# Confirm window map

Throwaway lookalike of the two screenshots (09:42 v1 with pins, 09:43 v2 after revise).

- HTML: `.scratch/propose-send-edit-revise/confirm-windows.html`
- Open: `open .scratch/propose-send-edit-revise/confirm-windows.html`
- Live copy of this table is the JSON in that file (`#swift-map`). The inspector shows the same rows.

Name a part by its **id** (one instance) or its **data-map** (the Swift view, shared when both windows draw it).

Example: “`v2-change-before-1` is too short” → `versionChanges` pair.before in `MailGent/SendProposalEditDialog.swift`, the strikethrough “server migration plan”.

## Which still is which

| Window | id | What the still shows |
|---|---|---|
| Left, 09:42 | `v1-window` | Review, two pins, status “Draft”, violet pin wash + numbered badges in the body. No version chevrons. |
| Right, 09:43 | `v2-window` | Same confirm after `applyAgentDraft`. Pins cleared, so no passage strip. Status “Draft v2”, chevrons, `v1 → v2 · Ask to look`, blue wash + underline on the new passages. No numbered badges in the body. |

`‹` on the right window calls the same path as `stepBack` and shows read-only v1 (`v2-status-viewing`, `v2-body-past`). `›` is `stepForward`.

## On screen → Swift

| data-map | ids | Swift | File |
|---|---|---|---|
| `window` | `v1-window`, `v2-window` | `HostedWindow` from `makeWindow` in `runSendProposalConfirm`. Content 560×620 with no case context. Miniaturize removed. | `MailGent/CompanionWindow.swift` |
| `titlebar` | `v1-titlebar`, `v2-titlebar` | NSWindow titlebar. Not SwiftUI. | `MailGent/CompanionWindow.swift` |
| `traffic-close` | `v1-traffic-close`, `v2-traffic-close` | Close → `onCancel` → `finishSendProposal(.cancel)` | `MailGent/CompanionWindow.swift` |
| `traffic-mini` | `v1-traffic-mini`, `v2-traffic-mini` | `.miniaturizable` removed, so the middle light is dead | `MailGent/CompanionWindow.swift` |
| `traffic-zoom` | `v1-traffic-zoom`, `v2-traffic-zoom` | Green zoom. Resizable stays on. | `MailGent/CompanionWindow.swift` |
| `title` | `v1-title`, `v2-title` | `SendProposalEditModel.windowTitle`. Review → “Send proposed mail?” | `MailGent/SendProposalEditModel.swift` |
| `expires` | `v1-expires`, `v2-expires` | `ProposeSendExpiryTitlebarLabel`. Stills frozen at 59:25 and 58:09. | `MailGent/ProposeSendExpiryTitlebarLabel.swift` |
| `chrome` | `v1-chrome`, `v2-chrome` | `SendProposalEditDialog.body`. Pad 12, gap 12. | `MailGent/SendProposalEditDialog.swift` |
| `lead` | `v1-lead`, `v2-lead` | `lead`. Review only. | `MailGent/SendProposalEditDialog.swift` |
| `lead-icon` | `v1-lead-icon`, `v2-lead-icon` | `Image(systemName: "paperplane.fill")`, 18pt semibold, orange | `MailGent/SendProposalEditDialog.swift` |
| `lead-copy` | `v1-lead-copy`, `v2-lead-copy` | “\(agentName) wants to send this message via Apple Mail”. Callout medium, secondary. | `MailGent/SendProposalEditDialog.swift` |
| `card` | `v1-card`, `v2-card` | `editorColumn`. Radius 10, stroke primary 0.12. | `MailGent/SendProposalEditDialog.swift` |
| `envelope` | `v1-envelope`, `v2-envelope` | `envelope` | `MailGent/SendProposalEditDialog.swift` |
| `field-to` | `v1-field-to`, `v2-field-to` | `field("To")` → `$model.toLine` | `MailGent/SendProposalEditDialog.swift` |
| `field-cc` | `v1-field-cc`, `v2-field-cc` | `field("Cc")`. Row stays when empty. | `MailGent/SendProposalEditDialog.swift` |
| `field-bcc` | `v1-field-bcc`, `v2-field-bcc` | `field("Bcc")`. Row stays when empty. | `MailGent/SendProposalEditDialog.swift` |
| `field-subject` | `v1-field-subject`, `v2-field-subject` | `field("Subject")` | `MailGent/SendProposalEditDialog.swift` |
| `field-label` | `v1-to-label`, `v1-cc-label`, `v1-bcc-label`, `v1-subject-label`, and the `v2-` twins | Caption, secondary, width 52 | `MailGent/SendProposalEditDialog.swift` |
| `field-value` | `v1-to-value`, `v1-cc-value`, `v1-bcc-value`, `v1-subject-value`, and the `v2-` twins | Plain `TextField`, caption. Read-only on a past version. | `MailGent/SendProposalEditDialog.swift` |
| `refs` | `v1-refs` only | `referencesStrip`. Hidden when `pins` is empty. v2 cleared pins in `applyAgentDraft`. | `MailGent/SendProposalEditDialog.swift` |
| `refs-head` | `v1-refs-head` | “Passages for Cursor's attention · count · sent on Ask to look, Ask to revise, or Send”. 11pt semibold violet. | `MailGent/SendProposalEditDialog.swift` |
| `ref` | `v1-ref-1`, `v1-ref-2` | `ReferenceNoteRow` | `MailGent/SendProposalEditDialog.swift` |
| `ref-badge` | `v1-ref-badge-1`, `v1-ref-badge-2` | 20×20 violet circle, white 11pt | `MailGent/SendProposalEditDialog.swift` |
| `ref-quote` | `v1-ref-quote-1`, `v1-ref-quote-2` | `quoteLabel`. Italic caption, one line, ellipsis. | `MailGent/SendProposalEditDialog.swift` |
| `ref-note` | `v1-ref-note-1`, `v1-ref-note-2` | Note `TextField`. Placeholder “What should Cursor look at here?” | `MailGent/SendProposalEditDialog.swift` |
| `ref-remove` | `v1-ref-remove-1`, `v1-ref-remove-2` | xmark. `model.pins.removeAll` for that id. | `MailGent/SendProposalEditDialog.swift` |
| `note-suggestions` | `v1-suggest-1`, `v1-suggest-2`, `v1-revise-suggest`, `v2-revise-suggest` | `PresetSuggestionList`. Opens while a note field is focused. Not in the stills. | `MailGent/SendProposalEditDialog.swift` |
| `status` | `v1-status`, `v2-status` | `statusStrip` | `MailGent/SendProposalEditDialog.swift` |
| `status-draft` | `v1-status-draft` (“Draft”), `v2-status-draft` (“Draft v2”) | “Draft” if `revisionRoundTrips == 0`, else “Draft v\(n+1)” | `MailGent/SendProposalEditDialog.swift` |
| `status-back` | `v2-status-back` | `stepBack`. chevron.left. Only when `versions.count > 1`. | `MailGent/SendProposalEditDialog.swift` |
| `status-forward` | `v2-status-forward` | `stepForward`. Disabled on the newest version. | `MailGent/SendProposalEditDialog.swift` |
| `status-viewing` | `v2-status-viewing` | “Viewing v1 · read-only · Agent proposal”. Shown after `‹`. | `MailGent/SendProposalEditDialog.swift` |
| `changes` | `v2-changes` | `versionChanges`. Nil on v1 and when stepped back. | `MailGent/SendProposalEditDialog.swift` |
| `changes-head` | `v2-changes-head` | “v1 → v2 · Ask to look”. Kind, not the longer origin, because rows carry pin notes. | `MailGent/SendProposalEditDialog.swift` |
| `change-row` | `v2-change-1`, `v2-change-2` | One `VersionChangePair` from `bodyChangeRows` | `MailGent/SendProposalEditModel.swift` draws in `SendProposalEditDialog.versionChanges` |
| `change-cue` | `v2-change-cue-1`, `v2-change-cue-2` | `VersionChangePair.PinCue`. 14×14 circle. | `MailGent/SendProposalEditDialog.swift` |
| `change-before` | `v2-change-before-1`, `v2-change-before-2` | `pair.before`. Secondary, strikethrough. Widened to the pinned quote. | `MailGent/SendProposalEditDialog.swift` |
| `change-arrow` | `v2-change-arrow-1`, `v2-change-arrow-2` | `Image(systemName: "arrow.right")` | `MailGent/SendProposalEditDialog.swift` |
| `change-after` | `v2-change-after-1`, `v2-change-after-2` | `pair.after` | `MailGent/SendProposalEditDialog.swift` |
| `change-note` | `v2-change-note-1`, `v2-change-note-2` | `cueNote`. “· ” plus the pin note. | `MailGent/SendProposalEditDialog.swift` |
| `body` | `v1-body`, `v2-body`, `v2-body-past` | `ProposalBodyEditor` / `ProposalBodyTextView`. Past version is `v2-body-past` (`isEditable: false`, `pins: []`). | `MailGent/ProposalBodyEditor.swift` |
| `mark-ref` | `v1-mark-1`, `v1-mark-2` | `refreshMarks` pin wash. Background `#efe8ff`, text `#4a2aa0`. | `MailGent/ProposalBodyEditor.swift` |
| `mark-badge` | `v1-badge-1`, `v1-badge-2` | `ProposalReferenceMarkerCell`. Sits at the end of the quote (`plan`①`:` and `Friday.`②). | `MailGent/ProposalBodyEditor.swift` |
| `mark-chg` | `v2-mark-1`, `v2-mark-2` | `refreshMarks` for `changedPassages`. Blue wash 13% and underline `#0071e3`. No badge, because live pins are empty. | `MailGent/ProposalBodyEditor.swift` |
| `caret` | `v1-caret`, `v2-caret` | Insertion point after “Alex” in the stills. Not its own SwiftUI view. | `MailGent/ProposalBodyEditor.swift` |
| `footer` | `v1-footer`, `v2-footer` | `footer` review branch. Spacing 8. | `MailGent/SendProposalEditDialog.swift` |
| `btn-cancel` | `v1-btn-cancel`, `v2-btn-cancel` | `Button("Cancel")` → `onCancel`. `AskPrimaryFooterButtonStyle(prominent: false)` | `MailGent/SendProposalEditDialog.swift` |
| `btn-look` | `v1-btn-look`, `v2-btn-look` | `Button("Ask agent to look")` → `askToLook()`. v2 is disabled (`pins` empty). The button style does not gray it. | `MailGent/SendProposalEditDialog.swift` |
| `btn-revise` | `v1-btn-revise`, `v2-btn-revise` | `Button("Ask to revise…")` → `showRevise`. Popover above the button. | `MailGent/SendProposalEditDialog.swift` |
| `btn-open` | `v1-btn-open`, `v2-btn-open` | `Button("Open in Mail")` → `onOpenInMail` | `MailGent/SendProposalEditDialog.swift` |
| `btn-send` | `v1-btn-send`, `v2-btn-send` | `Button("Send")`. Becomes “Send edited” only when `model.changes` is non-empty. Prominent style. | `MailGent/SendProposalEditDialog.swift` |

Button chrome for every footer button and “Send to agent” is `AskPrimaryFooterButtonStyle` in `MailGent/ConditionalAccessPrompt.swift` (radius 6, padding 8×5, 13pt).

## In the window, not in the stills

These open from the lookalike so the control behind a button can be tweaked. They are hidden until you use the control.

| data-map | ids | Swift | File |
|---|---|---|---|
| `refer-bubble` | `v1-bubble`, `v2-bubble` | `Coordinator.placeBubble`. Select body text. “Refer to agent's attention  ⇧⌘A”. Click → `model.refer(quote:)`. | `MailGent/ProposalBodyEditor.swift` |
| `revise-popover` | `v1-popover`, `v2-popover` | `revisePopover`. Width 320. | `MailGent/SendProposalEditDialog.swift` |
| `revise-chip` | `v1-revise-chip`, `v2-revise-chip` | Text “Whole draft” | `MailGent/SendProposalEditDialog.swift` |
| `revise-presets` | `v1-revise-presets`, `v2-revise-presets` | `FlowPresets` / `ProposalRevisePreset` | `MailGent/SendProposalEditDialog.swift`, cases in `MailStore/Sources/ProposalEdit.swift` |
| `revise-note` | `v1-revise-note`, `v2-revise-note` | `ProposalNoteField`, placeholder “Optional note” | `MailGent/SendProposalEditDialog.swift` |
| `revise-send` | `v1-revise-send`, `v2-revise-send` | `Button("Send to agent")` → `onInterim(.reviseRequested)` | `MailGent/SendProposalEditDialog.swift` |

## Swift that these stills do not show

Do not treat a tweak to the lookalike as a request to invent these. They are other branches of the same dialog.

| Swift | When it appears |
|---|---|
| `phaseBanner` | `waitingRevise`, `waitingAttention`, `sending`, `handedOff`, `failed`. Replaces `lead`. |
| `SendProposalContextThreadView` | Only when a case context resolved. These stills have none, so the window is 560 wide, not 820. |
| “Edited · N changes” + Revert | Human edited the draft (`model.changes` non-empty). |
| “Send, Open in Mail, or Cancel” | `revisionRoundTrips` has hit the cap (5). |
| “Editing turns this into plain text.” | HTML body not yet unlocked. |
| Secret pill (`ProposalTokenCell`) and “redacted for agent” | A secret constant in the body or in a quote. |
| `SendProposalPromptDialog` | The non-experimental confirm. These stills are `SendProposalEditDialog` (Settings → Experimental → Propose-send edit and revise). |
