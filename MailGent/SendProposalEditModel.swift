import Foundation
import MailStore

/// Confirm state for the experimental edit / refer / revise window.
/// The off-toggle path keeps `SendProposalConfirmModel` and does not use this.
@MainActor
final class SendProposalEditModel: ObservableObject {
    enum Phase: Equatable {
        case review
        case waitingRevise
        case waitingAttention
        case sending
        case handedOff
        case failed(String)
    }

    struct Baseline: Equatable {
        var to: [String]
        var cc: [String]
        var bcc: [String]
        var subject: String
        var body: String
    }

    /// A stored draft state. v1 is the agent's original proposal; every in-place
    /// agent revision appends one. Past versions are read-only previews.
    struct DraftVersion: Identifiable, Equatable {
        let id: Int
        var toLine: String
        var ccLine: String
        var bccLine: String
        var subject: String
        var tokenizedBody: String
        var origin: String
        /// Ask kind without the per-pin notes, e.g. "Ask to look" (shown in the
        /// summary header when the rows carry their own instructions).
        var kind: String
        /// Pins that travelled with the ask that produced this version, in chip order.
        var pins: [ProposalPin]
        /// Agent-reported Ask/Rewrite outcomes keyed to the pins that produced this version.
        var results: [ProposalInstructionResult]
    }

    enum DraftField: Equatable {
        case to, cc, bcc, subject
    }

    @Published var phase: Phase = .review
    @Published var proposal: SendProposal
    @Published var toLine: String
    @Published var ccLine: String
    @Published var bccLine: String
    @Published var subject: String
    @Published var tokenizedBody: String
    @Published var pins: [ProposalPin] = []
    @Published var referencedEventIDs: Set<String> = []
    @Published var plainTextUnlocked = false
    @Published var revisionRoundTrips = 0
    @Published var resolved: ProposeSendResolvedContext?
    @Published private(set) var versions: [DraftVersion] = []
    @Published var selectedReferenceID: String?
    @Published var expandedReferenceID: String?
    @Published var selectedChangeID: Int?
    @Published var expandedChangeID: Int?
    @Published var changesVisible = true
    @Published private(set) var focusRequest = 0
    private var revertedChangeIDsByVersion: [Int: Set<Int>] = [:]
    /// Index into `versions`, or nil when viewing the latest draft.
    @Published var viewingIndex: Int?
    /// How the user asked the agent to change the draft (set at ask time,
    /// consumed as the next version's origin when a revision lands).
    @Published private(set) var pendingAskOrigin: String?
    /// Ask kind without notes, stored on the next version for the summary header.
    @Published private(set) var pendingAskKind: String?
    /// Pins that will travel with the next revision (snapshot taken at ask time),
    /// so the new version's change rows can carry pin chip numbers and notes.
    @Published private(set) var pendingAskPins: [ProposalPin] = []

    let constants: [SecretConstant]
    let agentID: String
    private(set) var baseline: Baseline

    init(proposal: SendProposal, constants: [SecretConstant], agentID: String) {
        self.proposal = proposal
        self.constants = constants
        self.agentID = agentID
        let base = Self.baseline(for: proposal, constants: constants, agentID: agentID)
        self.baseline = base
        self.toLine = ProposalEnvelopeDiff.join(base.to)
        self.ccLine = ProposalEnvelopeDiff.join(base.cc)
        self.bccLine = ProposalEnvelopeDiff.join(base.bcc)
        self.subject = base.subject
        self.tokenizedBody = base.body
        self.plainTextUnlocked = !MailMIME.bodyLooksLikeHTML(base.body)
        self.versions = [Self.version(1, origin: "Agent proposal", kind: "Agent proposal", from: base)]
        self.viewingIndex = nil
    }

    var isReview: Bool {
        if case .review = phase { return true }
        return false
    }

    var windowTitle: String {
        switch phase {
        case .review: "Send proposed mail?"
        case .waitingRevise: "Waiting for Cursor"
        case .waitingAttention: "Waiting for Cursor"
        case .sending: "Sending…"
        case .handedOff: "Handed to Mail"
        case .failed: "Send failed"
        }
    }

    var bodyIsHTML: Bool {
        MailMIME.bodyLooksLikeHTML(baseline.body) && !plainTextUnlocked
    }

    var canRevise: Bool {
        isReview && revisionRoundTrips < PendingProposalRegistry.revisionCap
    }

    var changes: ProposalChanges {
        ProposalPayloadBuilder.changes(
            beforeTo: baseline.to,
            afterTo: ProposalEnvelopeDiff.split(toLine),
            beforeCc: baseline.cc,
            afterCc: ProposalEnvelopeDiff.split(ccLine),
            beforeBcc: baseline.bcc,
            afterBcc: ProposalEnvelopeDiff.split(bccLine),
            beforeSubject: baseline.subject,
            afterSubject: subject,
            beforeBody: baseline.body,
            afterBody: currentTokenizedBody,
            constants: constants,
            agentID: agentID
        )
    }

    var addedRecipients: [String] {
        ProposalEnvelopeDiff.added(
            before: baseline.to + baseline.cc + baseline.bcc,
            after: ProposalEnvelopeDiff.split(toLine)
                + ProposalEnvelopeDiff.split(ccLine)
                + ProposalEnvelopeDiff.split(bccLine)
        )
    }

    var currentTokenizedBody: String {
        ProposalBodyTokens.literalsToTokens(tokenizedBody, constants: constants, agentID: agentID)
    }

    func unlockPlainText() {
        tokenizedBody = MailMIME.plainText(fromHTML: tokenizedBody)
        plainTextUnlocked = true
    }

    func revert() {
        toLine = ProposalEnvelopeDiff.join(baseline.to)
        ccLine = ProposalEnvelopeDiff.join(baseline.cc)
        bccLine = ProposalEnvelopeDiff.join(baseline.bcc)
        subject = baseline.subject
        tokenizedBody = baseline.body
        plainTextUnlocked = !MailMIME.bodyLooksLikeHTML(baseline.body)
    }

    func refer(quote: String) {
        let tokenized = ProposalBodyTokens.literalsToTokens(quote, constants: constants, agentID: agentID)
        let snapped = tokenized
        guard !snapped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !pins.contains(where: { $0.quote == snapped }) else { return }
        pins.append(ProposalPin(id: "r\(pins.count + 1)", quote: snapped))
    }

    func focusReference(_ id: String) {
        guard pins.contains(where: { $0.id == id }) else { return }
        selectedReferenceID = id
        selectedChangeID = nil
        focusRequest &+= 1
    }

    func toggleReferenceExpansion(_ id: String) {
        focusReference(id)
        expandedReferenceID = expandedReferenceID == id ? nil : id
    }

    func removeReference(_ id: String) {
        pins.removeAll { $0.id == id }
        if selectedReferenceID == id { selectedReferenceID = nil }
        if expandedReferenceID == id { expandedReferenceID = nil }
    }

    func focusChange(_ id: Int) {
        guard displayedVersionChangeSummary?.pairs.contains(where: { $0.id == id }) == true else { return }
        selectedChangeID = id
        selectedReferenceID = nil
        focusRequest &+= 1
    }

    func toggleChangeExpansion(_ id: Int) {
        focusChange(id)
        expandedChangeID = expandedChangeID == id ? nil : id
    }

    func toggleChangesVisibility() {
        changesVisible.toggle()
    }

    func revertChange(_ id: Int) {
        guard !viewingPast,
              let summary = displayedVersionChangeSummary,
              let pair = summary.pairs.first(where: { $0.id == id })
        else {
            return
        }
        switch pair.field {
        case .to:
            toLine = pair.revertValue
        case .cc:
            ccLine = pair.revertValue
        case .bcc:
            bccLine = pair.revertValue
        case .subject:
            subject = pair.revertValue
        case nil:
            guard pair.kind == .body else { return }
            if pair.currentValue.isEmpty {
                tokenizedBody += pair.revertValue
            } else if let range = tokenizedBody.range(of: pair.currentValue) {
                tokenizedBody.replaceSubrange(range, with: pair.revertValue)
            } else {
                return
            }
        }
        revertedChangeIDsByVersion[summary.toID, default: []].insert(id)
        if selectedChangeID == id { selectedChangeID = nil }
        if expandedChangeID == id { expandedChangeID = nil }
    }

    func anchoredReferences() -> [ProposalReferenceRecord] {
        ProposalPins.anchor(pins, in: currentTokenizedBody) { text in
            ProposalRedaction.redact(text, constants: constants, agentID: agentID)
        }
    }

    func replyContext(from resolved: ProposeSendResolvedContext?) -> ProposalReplyContext? {
        guard let resolved else { return nil }
        let shown = resolved.items.filter { !$0.isDraft }.map(\.id)
        let referenced = shown.filter { referencedEventIDs.contains($0) }
        return ProposalReplyContext(
            casePath: resolved.casePath,
            caseLabel: resolved.caseLabel,
            shownEventIds: shown,
            referencedEventIds: referenced
        )
    }

    func sendPayload() -> ProposalAgentPayload {
        let edits = changes
        return ProposalPayloadBuilder.send(
            proposalId: proposal.id,
            changes: edits,
            sentBody: edits.isEmpty
                ? nil
                : ProposalRedaction.redact(currentTokenizedBody, constants: constants, agentID: agentID),
            references: anchoredReferences(),
            context: replyContext(from: resolved)
        )
    }

    func revisePayload(presets: [String], note: String) -> ProposalAgentPayload {
        ProposalPayloadBuilder.revise(
            proposalId: proposal.id,
            presets: presets,
            note: note,
            currentBody: currentTokenizedBody,
            userEdits: changes,
            references: anchoredReferences(),
            context: replyContext(from: resolved),
            constants: constants,
            agentID: agentID
        )
    }

    func attentionPayload() -> ProposalAgentPayload {
        ProposalPayloadBuilder.attention(
            proposalId: proposal.id,
            userEdits: changes,
            references: anchoredReferences(),
            context: replyContext(from: resolved)
        )
    }

    func deliveredProposal() -> SendProposal {
        let tokenized = currentTokenizedBody
        let catalog = Dictionary(uniqueKeysWithValues: constants.map { ($0.name, $0) })
        let resolved: String
        let spans: [SecretConstantResolveSpan]
        let missing: [String]
        do {
            let result = try SecretConstantResolver.resolve(body: tokenized, catalog: catalog)
            resolved = result.resolved
            spans = result.spans
            missing = []
        } catch let SecretConstantResolveError.missingNames(names) {
            resolved = tokenized
            spans = []
            missing = names
        } catch {
            resolved = tokenized
            spans = []
            missing = []
        }
        return SendProposal(
            id: proposal.id,
            agentName: proposal.agentName,
            to: ProposalEnvelopeDiff.split(toLine),
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            body: resolved,
            cc: ProposalEnvelopeDiff.split(ccLine),
            bcc: ProposalEnvelopeDiff.split(bccLine),
            sender: proposal.sender,
            context: proposal.context,
            secretConstantSpans: spans,
            secretConstantMissing: missing,
            tokenizedBody: tokenized
        )
    }

    /// Agent swapped the draft in place. Pins are consumed by the revision (the
    /// agent already received them); the deadline does not move.
    func applyAgentDraft(
        _ proposal: SendProposal,
        roundTrips: Int,
        resolved: ProposeSendResolvedContext?,
        results: [ProposalInstructionResult] = []
    ) {
        self.proposal = proposal
        baseline = Self.baseline(for: proposal, constants: constants, agentID: agentID)
        toLine = ProposalEnvelopeDiff.join(baseline.to)
        ccLine = ProposalEnvelopeDiff.join(baseline.cc)
        bccLine = ProposalEnvelopeDiff.join(baseline.bcc)
        subject = baseline.subject
        tokenizedBody = baseline.body
        plainTextUnlocked = !MailMIME.bodyLooksLikeHTML(baseline.body)
        revisionRoundTrips = roundTrips
        if let resolved { self.resolved = resolved }
        let origin = pendingAskOrigin ?? "Agent revision"
        let kind = pendingAskKind ?? "Agent revision"
        let askPins = pendingAskPins
        pendingAskOrigin = nil
        pendingAskKind = nil
        pendingAskPins = []
        versions.append(
            Self.version(
                (versions.last?.id ?? 0) + 1,
                origin: origin,
                kind: kind,
                pins: askPins,
                results: results,
                from: baseline
            )
        )
        viewingIndex = nil
        pins = []
        selectedReferenceID = nil
        expandedReferenceID = nil
        selectedChangeID = nil
        expandedChangeID = nil
        changesVisible = true
        phase = .review
    }

    /// Records why the user asked the agent to change the draft; becomes the next
    /// version's origin if a revision lands.
    func stageAskOriginRevise(presets: [String], note: String) {
        let constants = self.constants
        let agentID = self.agentID
        let redact: (String) -> String = { ProposalRedaction.redact($0, constants: constants, agentID: agentID) }
        var parts = presets
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { parts.append(redact(trimmed)) }
        pendingAskOrigin = parts.isEmpty ? "Ask to revise" : "Ask to revise · " + parts.joined(separator: " · ")
        pendingAskKind = "Ask to revise"
        pendingAskPins = pins
    }

    func stageAskOriginAttention() {
        let constants = self.constants
        let agentID = self.agentID
        let redact: (String) -> String = { ProposalRedaction.redact($0, constants: constants, agentID: agentID) }
        let notes = pins.map(\.note).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        pendingAskOrigin = notes.isEmpty ? "Ask to look" : "Ask to look · " + redact(notes.joined(separator: " · "))
        pendingAskKind = "Ask to look"
        pendingAskPins = pins
    }

    // MARK: Draft version history

    var viewingPast: Bool { viewedVersion != nil }

    /// The version on display when the user stepped back, else nil (latest).
    var viewedVersion: DraftVersion? {
        guard let viewingIndex, versions.indices.contains(viewingIndex), viewingIndex != versions.count - 1 else {
            return nil
        }
        return versions[viewingIndex]
    }

    var canStepBack: Bool {
        versions.count > 1 && (viewingIndex ?? versions.count - 1) > 0
    }

    var canStepForward: Bool {
        viewingIndex != nil
    }

    func stepBack() {
        guard canStepBack else { return }
        viewingIndex = (viewingIndex ?? versions.count - 1) - 1
    }

    func stepForward() {
        guard canStepForward else { return }
        let next = (viewingIndex ?? versions.count - 1) + 1
        viewingIndex = next >= versions.count - 1 ? nil : next
    }

    func value(_ field: DraftField, in version: DraftVersion) -> String {
        switch field {
        case .to: version.toLine
        case .cc: version.ccLine
        case .bcc: version.bccLine
        case .subject: version.subject
        }
    }

    /// Change count of a stored version against the one before it (display only).
    /// v1 has no previous version.
    func versionChangeCount(_ versionID: Int) -> Int? {
        guard let index = versions.firstIndex(where: { $0.id == versionID }), index > 0 else { return nil }
        let previous = versions[index - 1]
        let current = versions[index]
        return ProposalPayloadBuilder.changes(
            beforeTo: ProposalEnvelopeDiff.split(previous.toLine),
            afterTo: ProposalEnvelopeDiff.split(current.toLine),
            beforeCc: ProposalEnvelopeDiff.split(previous.ccLine),
            afterCc: ProposalEnvelopeDiff.split(current.ccLine),
            beforeBcc: ProposalEnvelopeDiff.split(previous.bccLine),
            afterBcc: ProposalEnvelopeDiff.split(current.bccLine),
            beforeSubject: previous.subject,
            afterSubject: current.subject,
            beforeBody: previous.tokenizedBody,
            afterBody: current.tokenizedBody,
            constants: constants,
            agentID: agentID
        ).count
    }

    /// Before → after pairs owned by the version on screen. The displayed version
    /// owns its own backward diff (v2 shows v1 → v2); v1 is a quiet snapshot with none.
    struct VersionChangePair: Identifiable, Equatable {
        enum Kind: Equatable { case recipient, subject, body, result }
        /// A pin linked to this change: its chip number and the note behind it.
        struct PinCue: Equatable {
            let number: Int
            let note: String
        }
        struct InstructionOutcome: Equatable {
            let instruction: ProposalPassageInstruction
            let result: ProposalInstructionResult?
        }
        let id: Int
        let kind: Kind
        let before: String
        let after: String
        var cues: [PinCue]
        var instructionOutcomes: [InstructionOutcome]
        /// Replacement text in the shown body. The preview highlights this passage.
        var changedPassage: String?
        var field: DraftField?
        /// Unredacted local values used only to restore this one change in the human-facing editor.
        var revertValue: String
        var currentValue: String
    }

    struct VersionChangeSummary: Equatable {
        let fromID: Int
        let toID: Int
        /// Ask kind without notes, e.g. "Ask to look".
        let kind: String
        /// Full origin (kind + notes) — header fallback when no row carries a pin cue.
        let origin: String
        let pairs: [VersionChangePair]

        /// Rows carry per-pin instructions, so the header shows the ask kind only.
        var rowsCarryInstructions: Bool {
            pairs.contains { !$0.cues.isEmpty }
        }
    }

    var displayedVersionChangeSummary: VersionChangeSummary? {
        let index = viewingIndex ?? versions.count - 1
        guard versions.count > 1, versions.indices.contains(index), index > 0 else { return nil }
        let summary = versionChangeSummary(
            from: versions[index - 1],
            to: versions[index]
        )
        let reverted = revertedChangeIDsByVersion[summary.toID] ?? []
        return VersionChangeSummary(
            fromID: summary.fromID,
            toID: summary.toID,
            kind: summary.kind,
            origin: summary.origin,
            pairs: summary.pairs.filter { !reverted.contains($0.id) }
        )
    }

    private func versionChangeSummary(
        from before: DraftVersion,
        to after: DraftVersion
    ) -> VersionChangeSummary {
        let constants = self.constants
        let agentID = self.agentID
        let redact: (String) -> String = { ProposalRedaction.redact($0, constants: constants, agentID: agentID) }
        var pairs: [VersionChangePair] = []
        func addPair(
            _ kind: VersionChangePair.Kind,
            field: DraftField,
            before rawBefore: String,
            after rawAfter: String,
            _ swap: ProposalFieldSwap?
        ) {
            guard let swap else { return }
            pairs.append(
                VersionChangePair(
                    id: pairs.count,
                    kind: kind,
                    before: swap.before,
                    after: swap.after,
                    cues: [],
                    instructionOutcomes: [],
                    changedPassage: nil,
                    field: field,
                    revertValue: rawBefore,
                    currentValue: rawAfter
                )
            )
        }
        addPair(.recipient, field: .to, before: before.toLine, after: after.toLine, ProposalEnvelopeDiff.swap(
            before: ProposalEnvelopeDiff.split(before.toLine),
            after: ProposalEnvelopeDiff.split(after.toLine),
            redact: redact
        ))
        addPair(.recipient, field: .cc, before: before.ccLine, after: after.ccLine, ProposalEnvelopeDiff.swap(
            before: ProposalEnvelopeDiff.split(before.ccLine),
            after: ProposalEnvelopeDiff.split(after.ccLine),
            redact: redact
        ))
        addPair(.recipient, field: .bcc, before: before.bccLine, after: after.bccLine, ProposalEnvelopeDiff.swap(
            before: ProposalEnvelopeDiff.split(before.bccLine),
            after: ProposalEnvelopeDiff.split(after.bccLine),
            redact: redact
        ))
        addPair(
            .subject,
            field: .subject,
            before: before.subject,
            after: after.subject,
            ProposalEnvelopeDiff.swap(before: before.subject, after: after.subject, redact: redact)
        )
        let bodyRows = bodyChangeRows(
            beforeBody: before.tokenizedBody,
            afterBody: after.tokenizedBody,
            pins: after.pins,
            redact: redact
        )
        for row in bodyRows {
            pairs.append(VersionChangePair(
                id: pairs.count,
                kind: .body,
                before: row.before,
                after: row.after,
                cues: row.cues,
                instructionOutcomes: [],
                changedPassage: row.passage,
                field: nil,
                revertValue: row.rawBefore,
                currentValue: row.rawAfter
            ))
        }

        let results = Dictionary(
            uniqueKeysWithValues: after.results.map {
                ("\($0.referenceID)\u{1f}\($0.instructionID)", $0)
            }
        )
        for (pinIndex, pin) in after.pins.enumerated() where !pin.instructions.isEmpty {
            let outcomes = pin.instructions.map { instruction in
                VersionChangePair.InstructionOutcome(
                    instruction: instruction,
                    result: results["\(pin.id)\u{1f}\(instruction.id)"]
                )
            }
            let cue = Self.pinCue(pin, index: pinIndex, redact: redact)
            if let pairIndex = pairs.firstIndex(where: { pair in
                pair.cues.contains(where: { $0.number == cue.number })
            }) {
                pairs[pairIndex].instructionOutcomes.append(contentsOf: outcomes)
            } else {
                pairs.append(
                    VersionChangePair(
                        id: pairs.count,
                        kind: .result,
                        before: redact(pin.quote),
                        after: "",
                        cues: [cue],
                        instructionOutcomes: outcomes,
                        changedPassage: nil,
                        field: nil,
                        revertValue: "",
                        currentValue: ""
                    )
                )
            }
        }

        return VersionChangeSummary(fromID: before.id, toID: after.id, kind: after.kind, origin: after.origin, pairs: pairs)
    }

    /// Passages in the body on screen that this version changed. Empty on v1.
    var displayedChangePassages: [String] {
        guard changesVisible else { return [] }
        return displayedVersionChangeSummary?.pairs.compactMap(\.changedPassage) ?? []
    }

    var focusedPassage: String? {
        if let selectedReferenceID {
            return pins.first(where: { $0.id == selectedReferenceID })?.quote
        }
        if let selectedChangeID,
           let pair = displayedVersionChangeSummary?.pairs.first(where: { $0.id == selectedChangeID })
        {
            return pair.changedPassage ?? (pair.kind == .result ? pair.before : nil)
        }
        return nil
    }

    private struct BodyChangeRow {
        var before: String
        var after: String
        var rawBefore: String
        var rawAfter: String
        var cues: [VersionChangePair.PinCue]
        var passage: String?
    }

    /// Word hunks, widened to a pin when the pinned quote covers the change.
    /// "plan:" → "initiative:" becomes "server migration plan" → "server migration initiative"
    /// so the row matches the passage the user pinned, not the smallest token.
    private func bodyChangeRows(
        beforeBody: String,
        afterBody: String,
        pins: [ProposalPin],
        redact: (String) -> String
    ) -> [BodyChangeRow] {
        let spans = ProposalBodyDiff.spans(before: beforeBody, after: afterBody)
        struct Draft {
            var order: Int
            var before: String
            var after: String
            var rawBefore: String
            var rawAfter: String
            var passage: String
            var cues: [VersionChangePair.PinCue]
        }
        var consumed = Set<Int>()
        var drafts: [Draft] = []

        for (pinIndex, pin) in pins.enumerated() {
            let quote = pin.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quote.isEmpty, let quoteRange = Self.utf16Range(of: quote, in: beforeBody) else { continue }
            let hits = spans.enumerated().filter { _, span in
                span.beforeStart < quoteRange.upperBound && span.beforeEnd > quoteRange.lowerBound
            }
            guard let first = hits.first?.element, let last = hits.last?.element else { continue }
            let cue = Self.pinCue(pin, index: pinIndex, redact: redact)
            if hits.allSatisfy({ consumed.contains($0.offset) }) {
                if let index = drafts.firstIndex(where: {
                    $0.before.localizedCaseInsensitiveContains(quote) || quote.localizedCaseInsensitiveContains($0.before)
                }) {
                    drafts[index].cues.append(cue)
                }
                continue
            }
            for hit in hits { consumed.insert(hit.offset) }

            var beforeStart = first.beforeStart
            var beforeEnd = last.beforeEnd
            var afterStart = first.afterStart
            var afterEnd = last.afterEnd
            let prefixLen = first.beforeStart - quoteRange.lowerBound
            if prefixLen >= 0 {
                beforeStart = quoteRange.lowerBound
                beforeEnd = quoteRange.upperBound
                afterStart = first.afterStart - prefixLen
                let overflow = last.beforeEnd - quoteRange.upperBound
                if overflow > 0 {
                    let extra = Self.utf16Slice(beforeBody, quoteRange.upperBound, last.beforeEnd)
                    let afterHunk = Self.utf16Slice(afterBody, last.afterStart, last.afterEnd)
                    if afterHunk.hasSuffix(extra) {
                        afterEnd -= (extra as NSString).length
                    }
                } else {
                    afterEnd += quoteRange.upperBound - last.beforeEnd
                }
            }
            let beforeText = Self.trim(Self.utf16Slice(beforeBody, beforeStart, beforeEnd))
            let afterText = Self.trim(Self.utf16Slice(afterBody, max(0, afterStart), max(afterStart, afterEnd)))
            drafts.append(Draft(
                order: beforeStart,
                before: redact(beforeText),
                after: redact(afterText),
                rawBefore: beforeText,
                rawAfter: afterText,
                passage: afterText,
                cues: [cue]
            ))
        }

        for (index, span) in spans.enumerated() where !consumed.contains(index) {
            drafts.append(Draft(
                order: span.beforeStart,
                before: redact(span.before),
                after: redact(span.after),
                rawBefore: span.before,
                rawAfter: span.after,
                passage: span.after,
                cues: []
            ))
        }

        let placed = Set(drafts.flatMap { $0.cues.map(\.number) })
        for (pinIndex, pin) in pins.enumerated() {
            let number = Int(pin.id.dropFirst("r".count)) ?? pinIndex + 1
            guard !placed.contains(number) else { continue }
            let quote = pin.quote.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !quote.isEmpty,
                  let index = drafts.firstIndex(where: {
                      !$0.before.isEmpty && (
                          $0.before.localizedCaseInsensitiveContains(quote)
                              || quote.localizedCaseInsensitiveContains($0.before)
                              || $0.after.localizedCaseInsensitiveContains(quote)
                              || quote.localizedCaseInsensitiveContains($0.after)
                      )
                  })
            else { continue }
            drafts[index].cues.append(Self.pinCue(pin, index: pinIndex, redact: redact))
        }

        return drafts.sorted { $0.order < $1.order }.map {
            BodyChangeRow(
                before: $0.before,
                after: $0.after,
                rawBefore: $0.rawBefore,
                rawAfter: $0.rawAfter,
                cues: $0.cues,
                passage: $0.passage.isEmpty ? nil : $0.passage
            )
        }
    }

    private static func pinCue(_ pin: ProposalPin, index: Int, redact: (String) -> String) -> VersionChangePair.PinCue {
        VersionChangePair.PinCue(
            number: Int(pin.id.dropFirst("r".count)) ?? index + 1,
            note: redact(pin.note)
        )
    }

    private static func utf16Range(of needle: String, in text: String) -> Range<Int>? {
        let found = (text as NSString).range(of: needle, options: [.caseInsensitive])
        guard found.location != NSNotFound else { return nil }
        return found.location..<(found.location + found.length)
    }

    private static func utf16Slice(_ text: String, _ start: Int, _ end: Int) -> String {
        let ns = text as NSString
        let loc = max(0, min(start, ns.length))
        let upper = max(loc, min(end, ns.length))
        return ns.substring(with: NSRange(location: loc, length: upper - loc))
    }

    private static func trim(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func version(
        _ id: Int,
        origin: String,
        kind: String? = nil,
        pins: [ProposalPin] = [],
        results: [ProposalInstructionResult] = [],
        from base: Baseline
    ) -> DraftVersion {
        DraftVersion(
            id: id,
            toLine: ProposalEnvelopeDiff.join(base.to),
            ccLine: ProposalEnvelopeDiff.join(base.cc),
            bccLine: ProposalEnvelopeDiff.join(base.bcc),
            subject: base.subject,
            tokenizedBody: base.body,
            origin: origin,
            kind: kind ?? origin,
            pins: pins,
            results: results
        )
    }

    private static func baseline(
        for proposal: SendProposal,
        constants: [SecretConstant],
        agentID: String
    ) -> Baseline {
        Baseline(
            to: proposal.to,
            cc: proposal.cc,
            bcc: proposal.bcc,
            subject: proposal.subject,
            body: ProposalBodyTokens.literalsToTokens(
                proposal.tokenizedBody,
                constants: constants,
                agentID: agentID
            )
        )
    }
}
