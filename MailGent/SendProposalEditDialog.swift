import AppKit
import MailStore
import SwiftUI

/// Experimental confirm window. Used only when Settings → Experimental → Propose-send edit and revise is on.
struct SendProposalEditDialog: View {
    @ObservedObject var model: SendProposalEditModel
    let shortcut: ProposalReferShortcut
    let notePresets: [String]
    let onSend: (SendProposal, ProposalAgentPayload) -> Void
    let onOpenInMail: (SendProposal) -> Void
    let onCancel: () -> Void
    let onRetry: (SendProposal) -> Void
    let onDone: () -> Void
    let onInterim: (SendProposalDecision, ProposalAgentPayload) -> Void
    var onOpenContextOriginal: (ContextThreadOriginal) -> Void = { _ in }

    @State private var showRevise = false
    @State private var revisePresets: Set<String> = []
    @State private var reviseNote = ""
    @State private var reviseNoteFocused = false
    @State private var contextThin = true
    @State private var selectedEventID: String? = "draft"
    @State private var spotlightDraft = true
    @State private var bodyHovered = false
    @State private var pageZoom: CGFloat = 1

    private static let envelopeLabelWidth: CGFloat = 52
    private static let zoomStep: CGFloat = 0.25
    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 1.5
    private var resolvedContext: ProposeSendResolvedContext? { model.resolved }
    private var showsContext: Bool { resolvedContext != nil }

    /// Follows the browsed draft (`deliveredProposal`), including past versions.
    private var usedSecretSummaries: [ProposeSendUsedSecretSummary] {
        let delivered = model.deliveredProposal()
        return ProposeSendUsedSecrets.summaries(
            body: delivered.body,
            spans: delivered.secretConstantSpans
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ConditionalAskLayout.gap) {
            if model.isReview {
                lead
            } else {
                phaseBanner
            }
            Group {
                if let resolved = resolvedContext {
                    split(resolved)
                } else {
                    editorColumn
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .opacity(model.phase == .handedOff || model.phase == .sending ? 0.72 : 1)
            .allowsHitTesting(model.isReview)
            if !usedSecretSummaries.isEmpty, model.isReview {
                ProposeSendSecretUsedStrip(summaries: usedSecretSummaries)
            }
            footer
        }
        .padding(ConditionalAskLayout.pad)
        .frame(
            minWidth: (showsContext ? SendProposalPromptDialog.contextWindowMinSize : SendProposalPromptDialog.windowMinSize).width,
            idealWidth: (showsContext ? SendProposalPromptDialog.contextWindowSize : SendProposalPromptDialog.windowSize).width,
            maxWidth: .infinity,
            minHeight: (showsContext ? SendProposalPromptDialog.contextWindowMinSize : SendProposalPromptDialog.windowMinSize).height,
            idealHeight: (showsContext ? SendProposalPromptDialog.contextWindowSize : SendProposalPromptDialog.windowSize).height,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var lead: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "paperplane.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.orange)
            Text("\(model.proposal.agentName) wants to send this message via Apple Mail")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isWaiting: Bool {
        switch model.phase {
        case .waitingRevise, .waitingAttention: true
        default: false
        }
    }

    private var phaseBanner: some View {
        let title: String
        let subtitle: String
        let tint: Color
        switch model.phase {
        case .waitingRevise:
            title = "Asked Cursor for a new draft"
            subtitle = "Waiting for propose_send with revises. The original deadline still applies."
            tint = Color.accentColor.opacity(0.08)
        case .waitingAttention:
            title = "Asked Cursor to look at \(model.pins.count) passage\(model.pins.count == 1 ? "" : "s")"
            subtitle = "Waiting for Cursor's reply. The draft stays as it is until Cursor proposes again."
            tint = Color.accentColor.opacity(0.08)
        case .sending:
            title = "Sending via Apple Mail…"
            subtitle = "Handing the message to Mail (Automation). Not waiting for Sent."
            tint = Color.accentColor.opacity(0.08)
        case .handedOff:
            title = "Handed to Apple Mail"
            subtitle = "Mail accepted the send. It may take a moment to appear in Sent."
            tint = Color.green.opacity(0.10)
        case let .failed(message):
            title = "Mail refused the send"
            subtitle = message
            tint = Color.red.opacity(0.08)
        case .review:
            title = ""
            subtitle = ""
            tint = .clear
        }
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if isWaiting {
                Button("Keep editing") { model.phase = .review }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .help("Go back to editing without waiting for the agent")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func split(_ resolved: ProposeSendResolvedContext) -> some View {
        HSplitView {
            SendProposalContextThreadView(
                resolved: resolved,
                thin: $contextThin,
                selectedID: $selectedEventID,
                spotlightDraft: $spotlightDraft,
                onOpenOriginal: onOpenContextOriginal,
                referencedEventIDs: $model.referencedEventIDs
            )
            .frame(
                minWidth: contextThin ? 124 : 220,
                idealWidth: contextThin ? 124 : 260,
                maxWidth: contextThin ? 124 : 420,
                maxHeight: .infinity
            )

            splitEditorColumn
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var editorColumn: some View {
        editorColumn(
            shape: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }

    private var splitEditorColumn: some View {
        editorColumn(
            shape: UnevenRoundedRectangle(
                cornerRadii: RectangleCornerRadii(
                    topLeading: 0,
                    bottomLeading: 0,
                    bottomTrailing: 10,
                    topTrailing: 10
                ),
                style: .continuous
            )
        )
    }

    private func editorColumn<S: InsettableShape>(shape: S) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            envelope
            statusStrip
            versionChanges
            bodyEditor
            referencesStrip
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(Color.primary.opacity(0.12))
        )
    }

    private var envelope: some View {
        VStack(alignment: .leading, spacing: 6) {
            field(
                "From",
                text: .constant(model.proposal.sender ?? "Apple Mail default account"),
                editable: false
            )
            field("To", text: envelopeBinding(.to))
            field("Cc", text: envelopeBinding(.cc))
            field("Bcc", text: envelopeBinding(.bcc))
            field("Subject", text: envelopeBinding(.subject))
            if !model.viewingPast, !model.addedRecipients.isEmpty {
                Text("Added: \(model.addedRecipients.joined(separator: ", "))")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(10)
    }

    /// Live binding for the current draft; a read-only binding when previewing a past version.
    private func envelopeBinding(_ field: SendProposalEditModel.DraftField) -> Binding<String> {
        if let past = model.viewedVersion {
            return Binding(
                get: { model.value(field, in: past) },
                set: { _ in }
            )
        }
        switch field {
        case .to: return $model.toLine
        case .cc: return $model.ccLine
        case .bcc: return $model.bccLine
        case .subject: return $model.subject
        }
    }

    private func field(_ label: String, text: Binding<String>, editable: Bool = true) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Self.envelopeLabelWidth, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.caption)
                .disabled(!editable || !model.isReview || model.viewingPast)
        }
    }

    private var referencesStrip: some View {
        Group {
            if !model.pins.isEmpty, model.phase != .handedOff, !model.viewingPast {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Passages for Cursor's attention · \(model.pins.count) · sent on Ask to look, Ask to revise, or Send")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.42, green: 0.25, blue: 0.82))
                    ForEach(Array(model.anchoredReferences().enumerated()), id: \.element.id) { index, reference in
                        FocusReferenceRow(
                            number: index + 1,
                            reference: reference,
                            note: pinNote(reference.id),
                            choices: ProposalPassageInstructions.choices(from: notePresets),
                            selected: selectedInstructions(reference.id),
                            expanded: model.expandedReferenceID == reference.id,
                            onFocus: { model.focusReference(reference.id) },
                            onToggleExpanded: { model.toggleReferenceExpansion(reference.id) },
                            onToggleInstruction: { toggleInstruction($0, referenceID: reference.id) },
                            onRemove: { model.removeReference(reference.id) }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(red: 0.980, green: 0.973, blue: 1))
            }
        }
    }

    private func pinNote(_ id: String) -> Binding<String> {
        Binding(
            get: { model.pins.first { $0.id == id }?.note ?? "" },
            set: { newValue in
                guard let index = model.pins.firstIndex(where: { $0.id == id }) else { return }
                model.pins[index].note = newValue
            }
        )
    }

    private func selectedInstructions(_ id: String) -> [ProposalPassageInstruction] {
        model.pins.first(where: { $0.id == id })?.instructions ?? []
    }

    private func toggleInstruction(_ instruction: ProposalPassageInstruction, referenceID: String) {
        guard let pinIndex = model.pins.firstIndex(where: { $0.id == referenceID }) else { return }
        if let index = model.pins[pinIndex].instructions.firstIndex(where: { $0.id == instruction.id }) {
            model.pins[pinIndex].instructions.remove(at: index)
        } else {
            model.pins[pinIndex].instructions.append(instruction)
            let order = Dictionary(
                uniqueKeysWithValues: ProposalPassageInstructions.choices(from: notePresets)
                    .enumerated()
                    .map { ($0.element.id, $0.offset) }
            )
            model.pins[pinIndex].instructions.sort {
                (order[$0.id] ?? .max) < (order[$1.id] ?? .max)
            }
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 8) {
            if model.versions.count > 1 {
                Button {
                    model.stepBack()
                } label: {
                    Image(systemName: "chevron.left").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.canStepBack ? Color.accentColor : .secondary)
                .disabled(!model.canStepBack)
                .help("View the previous draft version")
                Button {
                    model.stepForward()
                } label: {
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.canStepForward ? Color.accentColor : .secondary)
                .disabled(!model.canStepForward)
                .help("Return to the current draft")
            }
            if let past = model.viewedVersion {
                Text("Viewing v\(past.id) · read-only · \(past.origin)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else if model.changes.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(model.revisionRoundTrips == 0 ? "Draft" : "Draft v\(model.revisionRoundTrips + 1)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Edited · \(model.changes.count) change\(model.changes.count == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                Button("Revert") { model.revert() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }
            if model.revisionRoundTrips >= PendingProposalRegistry.revisionCap {
                Text("Send, Open in Mail, or Cancel")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if model.displayedVersionChangeSummary != nil, !model.viewingPast {
                ExpandingIconAction(
                    title: model.changesVisible ? "Hide changes" : "Show changes",
                    systemImage: model.changesVisible ? "eye.slash" : "eye",
                    action: model.toggleChangesVisibility
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.65))
    }

    /// Compact before → after list owned by the version on screen (v2 shows its
    /// own v1 → v2; v1 is a quiet snapshot with none).
    @ViewBuilder
    private var versionChanges: some View {
        if let summary = model.displayedVersionChangeSummary, model.changesVisible {
            VStack(alignment: .leading, spacing: 4) {
                Text("v\(summary.fromID) → v\(summary.toID) · \(summary.rowsCarryInstructions ? summary.kind : summary.origin)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.25, blue: 0.82))
                    .lineLimit(1)
                if summary.pairs.isEmpty {
                    Text("No remaining changes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(summary.pairs) { pair in
                    FocusChangeRow(
                        pair: pair,
                        expanded: model.expandedChangeID == pair.id,
                        canRevert: !model.viewingPast && pair.kind != .result,
                        onFocus: { model.focusChange(pair.id) },
                        onToggleExpanded: { model.toggleChangeExpansion(pair.id) },
                        onRevert: { model.revertChange(pair.id) }
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.45))
        }
    }

    private var bodyEditor: some View {
        ZStack(alignment: .bottomTrailing) {
            bodyEditorContent
            if !model.bodyIsHTML {
                AskPreviewHoverTracker(isHovering: $bodyHovered)
                    .allowsHitTesting(false)
                AskPreviewZoomControls(
                    zoom: pageZoom,
                    canZoomOut: pageZoom > Self.minZoom + 0.001,
                    canZoomIn: pageZoom < Self.maxZoom - 0.001,
                    onZoomOut: {
                        pageZoom = max(Self.minZoom, pageZoom - Self.zoomStep)
                    },
                    onZoomIn: {
                        pageZoom = min(Self.maxZoom, pageZoom + Self.zoomStep)
                    }
                )
                .padding(.trailing, 10)
                .padding(.bottom, 8)
                .opacity(bodyHovered ? 1 : 0)
                .allowsHitTesting(bodyHovered)
                .accessibilityHidden(!bodyHovered)
                .onHover { hovering in
                    if hovering { bodyHovered = true }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Draft preview")
        .accessibilityValue("\(Int((pageZoom * 100).rounded())) percent")
    }

    @ViewBuilder
    private var bodyEditorContent: some View {
        if model.bodyIsHTML {
            VStack(alignment: .leading, spacing: 8) {
                Text("Editing turns this into plain text.")
                    .font(.callout)
                Button("Edit as plain text") { model.unlockPlainText() }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let past = model.viewedVersion {
            ProposalBodyEditor(
                tokenized: .constant(past.tokenizedBody),
                constants: model.constants,
                agentID: model.agentID,
                pins: [],
                changedPassages: model.displayedChangePassages,
                focusedPassage: model.focusedPassage,
                focusRequest: model.focusRequest,
                shortcut: shortcut,
                isEditable: false,
                fontScale: pageZoom,
                onRefer: { _ in }
            )
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProposalBodyEditor(
                tokenized: $model.tokenizedBody,
                constants: model.constants,
                agentID: model.agentID,
                pins: model.pins,
                changedPassages: model.displayedChangePassages,
                focusedPassage: model.focusedPassage,
                focusRequest: model.focusRequest,
                shortcut: shortcut,
                isEditable: true,
                fontScale: pageZoom,
                onRefer: { quote in model.refer(quote: quote) }
            )
            .padding(.horizontal, 8)
            .frame(minHeight: 110)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var footer: some View {
        switch model.phase {
        case .review, .waitingRevise, .waitingAttention:
            HStack(spacing: 8) {
                Button("Cancel") { onCancel() }
                    .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
                    .keyboardShortcut(.cancelAction)
                Spacer(minLength: 8)
                Button("Ask agent to look") { askToLook() }
                    .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
                    .disabled(!model.canRevise || model.pins.isEmpty || !model.isReview)
                Button("Ask to revise…") { showRevise = true }
                    .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
                    .disabled(!model.canRevise)
                    .popover(isPresented: $showRevise, arrowEdge: .top) {
                        revisePopover
                    }
                Button("Open in Mail") { onOpenInMail(model.deliveredProposal()) }
                    .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
                    .disabled(!model.deliveredProposal().canDeliverSecretConstants)
                Button(model.changes.isEmpty ? "Send" : "Send edited") { onSend(model.deliveredProposal(), model.sendPayload()) }
                    .buttonStyle(AskPrimaryFooterButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.deliveredProposal().canDeliverSecretConstants || !model.isReview && model.phase != .waitingRevise && model.phase != .waitingAttention)
            }
        case .sending:
            Text("Working…").font(.caption).foregroundStyle(.secondary)
        case .handedOff:
            HStack {
                Spacer()
                Button("Done") { onDone() }
                    .buttonStyle(AskPrimaryFooterButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        case .failed:
            HStack {
                Button("Cancel") { onCancel() }
                    .buttonStyle(AskPrimaryFooterButtonStyle(prominent: false))
                Spacer()
                Button("Try again") { onRetry(model.deliveredProposal()) }
                    .buttonStyle(AskPrimaryFooterButtonStyle(prominent: true))
            }
        }
    }

    private var revisePopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Whole draft")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color(red: 0.937, green: 0.910, blue: 1)))
            FlowPresets(selected: $revisePresets)
            ProposalNoteField(
                text: $reviseNote,
                focused: $reviseNoteFocused,
                presets: notePresets,
                prompt: "Optional note"
            )
            Button("Send to agent") {
                let presets = ProposalRevisePreset.allCases.map(\.rawValue).filter { revisePresets.contains($0) }
                let payload = model.revisePayload(presets: presets, note: reviseNote)
                model.stageAskOriginRevise(presets: presets, note: reviseNote)
                showRevise = false
                model.phase = .waitingRevise
                onInterim(.reviseRequested, payload)
            }
            .buttonStyle(AskPrimaryFooterButtonStyle(prominent: true))
            .disabled(revisePresets.isEmpty && reviseNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
    }

    private func askToLook() {
        let payload = model.attentionPayload()
        model.stageAskOriginAttention()
        model.phase = .waitingAttention
        onInterim(.attentionRequested, payload)
    }
}

private struct FlowPresets: View {
    @Binding var selected: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ProposalRevisePreset.allCases, id: \.rawValue) { preset in
                let on = selected.contains(preset.rawValue)
                Button(preset.rawValue) {
                    if on { selected.remove(preset.rawValue) } else { selected.insert(preset.rawValue) }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.06)))
            }
        }
    }
}

private struct FocusReferenceRow: View {
    let number: Int
    let reference: ProposalReferenceRecord
    @Binding var note: String
    let choices: [ProposalPassageInstruction]
    let selected: [ProposalPassageInstruction]
    let expanded: Bool
    var onFocus: () -> Void
    var onToggleExpanded: () -> Void
    var onToggleInstruction: (ProposalPassageInstruction) -> Void
    var onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                FocusNumberButton(number: number, tint: Color(red: 0.42, green: 0.25, blue: 0.82), action: onFocus)
                Button(action: onToggleExpanded) {
                    HStack(spacing: 6) {
                        quoteLabel
                        Spacer(minLength: 0)
                        instructionIcons
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                ExpandingIconAction(title: "Remove", systemImage: "xmark", action: onRemove)
            }
            if expanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(choices) { instruction in
                        instructionChoice(instruction)
                    }
                    TextField("Anything else for this passage?", text: $note)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
                .padding(.leading, 26)
            }
        }
    }

    private var quoteLabel: some View {
        let parts = quoteParts(reference.quote)
        return HStack(spacing: 4) {
            Text(parts.visible)
                .font(.caption.italic())
                .strikethrough(reference.stale)
                .lineLimit(1)
            if parts.redacted {
                Text("🔒 redacted for agent")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.42, green: 0.227, blue: 0))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(Color(red: 1, green: 0.953, blue: 0.867)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var instructionIcons: some View {
        HStack(spacing: 3) {
            if selected.contains(where: { $0.kind == .ask || $0.kind == .askAndRewrite }) {
                InstructionIcon(kind: .ask)
            }
            if selected.contains(where: { $0.kind == .rewrite || $0.kind == .askAndRewrite }) {
                InstructionIcon(kind: .rewrite)
            }
        }
    }

    private func instructionChoice(_ instruction: ProposalPassageInstruction) -> some View {
        let isSelected = selected.contains(where: { $0.id == instruction.id })
        return Button {
            onToggleInstruction(instruction)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                Text(instruction.label)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                InstructionKindChips(instruction: instruction)
            }
            .font(.caption)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func quoteParts(_ quote: String) -> (visible: String, redacted: Bool) {
        let redacted = quote.contains("[redacted")
        let visible = quote.replacingOccurrences(
            of: #"\[\[mg:([a-z][a-z0-9_]*)\]\]"#,
            with: "🔒 $1",
            options: .regularExpression
        )
        return (visible, redacted || visible.contains("🔒"))
    }
}

private struct FocusNumberButton: View {
    let number: Int
    let tint: Color
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if hovered {
                    Image(systemName: "eye")
                        .font(.system(size: 9, weight: .bold))
                } else {
                    Text("\(number)")
                        .font(.system(size: 10, weight: .bold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: 17, height: 17)
            .background(Circle().fill(tint))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Select this passage in the draft")
    }
}

private struct InstructionIcon: View {
    let kind: ProposalInstructionKind

    var body: some View {
        Image(systemName: kind == .ask ? "questionmark" : "pencil")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(kind == .ask ? Color(red: 0.29, green: 0.17, blue: 0.63) : Color(red: 0.60, green: 0.30, blue: 0))
            .frame(width: 16, height: 16)
            .background(
                kind == .ask
                    ? Color(red: 0.937, green: 0.910, blue: 1)
                    : Color(red: 1, green: 0.945, blue: 0.871),
                in: RoundedRectangle(cornerRadius: 4)
            )
    }
}

private struct InstructionKindChips: View {
    let instruction: ProposalPassageInstruction

    var body: some View {
        HStack(spacing: 3) {
            if instruction.kind == .ask || instruction.kind == .askAndRewrite {
                chip("Ask", ask: true)
                if let answerShape = instruction.answerShape {
                    chip(answerMark(answerShape), ask: true)
                }
            }
            if instruction.kind == .rewrite || instruction.kind == .askAndRewrite {
                chip("Rewrite", ask: false)
            }
        }
    }

    private func chip(_ text: String, ask: Bool) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .padding(.horizontal, 4)
            .frame(height: 14)
            .background(
                ask ? Color(red: 0.937, green: 0.910, blue: 1) : Color(red: 1, green: 0.945, blue: 0.871),
                in: RoundedRectangle(cornerRadius: 3)
            )
            .foregroundStyle(ask ? Color(red: 0.29, green: 0.17, blue: 0.63) : Color(red: 0.60, green: 0.30, blue: 0))
    }

    private func answerMark(_ shape: ProposalAnswerShape) -> String {
        switch shape {
        case .yesNo: "✓✕"
        case .number: "#"
        case .choices: "ABC"
        case .text: "Aa"
        }
    }
}

private struct ExpandingIconAction: View {
    let title: String
    let systemImage: String
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if hovered {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .transition(.opacity)
                }
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(hovered ? Color.accentColor : .secondary)
            .frame(height: 16)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(title)
    }
}

private struct FocusChangeRow: View {
    let pair: SendProposalEditModel.VersionChangePair
    let expanded: Bool
    let canRevert: Bool
    var onFocus: () -> Void
    var onToggleExpanded: () -> Void
    var onRevert: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if let cue = pair.cues.first {
                FocusNumberButton(number: cue.number, tint: changeGreen, action: onFocus)
            } else {
                Color.clear.frame(width: 17, height: 17)
            }
            Button(action: onToggleExpanded) {
                Group {
                    if expanded {
                        expandedContent
                    } else {
                        compactContent
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if canRevert {
                ExpandingIconAction(title: "Revert", systemImage: "arrow.uturn.backward", action: onRevert)
            }
        }
        .font(.caption)
    }

    private var compactContent: some View {
        HStack(spacing: 6) {
            Text(pair.before)
                .strikethrough(pair.kind != .result)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(pair.kind == .result ? "?" : "→")
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            if pair.kind != .result {
                Text(pair.after)
                    .foregroundStyle(pair.kind == .body ? changeGreen : .primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                aggregateOutcome
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(pair.before)
                .strikethrough(pair.kind != .result)
                .foregroundStyle(.secondary)
            ForEach(Array(pair.instructionOutcomes.enumerated()), id: \.offset) { _, outcome in
                instructionOutcome(outcome)
            }
            if pair.kind != .result {
                Text("↓")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text(pair.after)
                    .foregroundStyle(pair.kind == .body ? changeGreen : .primary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var aggregateOutcome: some View {
        let reported = pair.instructionOutcomes.filter { $0.result != nil }
        let failed = reported.contains { $0.result?.status == .fail }
        let complete = reported.count == pair.instructionOutcomes.count
        return HStack(spacing: 5) {
            Image(systemName: failed ? "xmark.square.fill" : complete ? "checkmark.square.fill" : "square")
                .foregroundStyle(failed ? Color.red : complete ? changeGreen : .secondary)
            Text(
                failed
                    ? "Needs attention"
                    : complete
                        ? "Reported"
                        : "\(reported.count) of \(pair.instructionOutcomes.count) reported"
            )
                .lineLimit(1)
        }
    }

    private func instructionOutcome(
        _ outcome: SendProposalEditModel.VersionChangePair.InstructionOutcome
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: outcomeIcon(outcome.result))
                .foregroundStyle(outcomeColor(outcome.result))
            Text(outcome.instruction.label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(outcomeText(outcome.result))
                .foregroundStyle(outcome.result == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        }
        .font(.caption)
    }

    private func outcomeIcon(_ result: ProposalInstructionResult?) -> String {
        switch result?.status {
        case .pass: "checkmark.square.fill"
        case .fail: "xmark.square.fill"
        case nil: result == nil ? "square" : "minus.square"
        }
    }

    private func outcomeColor(_ result: ProposalInstructionResult?) -> Color {
        switch result?.status {
        case .pass: changeGreen
        case .fail: .red
        case nil: .secondary
        }
    }

    private func outcomeText(_ result: ProposalInstructionResult?) -> String {
        guard let result else { return "Unreported" }
        switch result.answer {
        case let .yesNo(value): return value ? "Yes" : "No"
        case let .number(value): return value.formatted()
        case let .choice(value), let .text(value): return value
        case nil:
            switch result.status {
            case .pass: return "Pass"
            case .fail: return "Fail"
            case nil: return "Reported"
            }
        }
    }

    private var changeGreen: Color {
        Color(red: 36.0 / 255, green: 138.0 / 255, blue: 61.0 / 255)
    }
}

private struct ProposalNoteField: View {
    @Binding var text: String
    @Binding var focused: Bool
    let presets: [String]
    let prompt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(prompt, text: $text, onEditingChanged: { focused = $0 })
                .textFieldStyle(.roundedBorder)
                .font(.caption)
            if focused {
                PresetSuggestionList(query: text, presets: presets) { picked in
                    text = picked
                    focused = false
                }
            }
        }
    }
}

private struct PresetSuggestionList: View {
    let query: String
    let presets: [String]
    var onPick: (String) -> Void

    var body: some View {
        let matches = ProposalNoteFuzzy.suggestions(query: query, presets: presets)
        VStack(alignment: .leading, spacing: 2) {
            if matches.isEmpty {
                Text("No matching preset — keep typing, your text is sent as-is.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Common instructions" : "Suggestions")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                ForEach(matches, id: \.self) { preset in
                    Button(preset) { onPick(preset) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.top, 2)
    }
}
