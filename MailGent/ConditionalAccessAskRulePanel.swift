import SwiftUI
import MailStore

/// Where the Ask rule attaches for the prompting agent.
public enum AskRuleEnableScope: String, CaseIterable, Identifiable, Sendable {
    /// Ask `accountID` + `placement` (default).
    case thisMailbox
    /// Ask `accountID` with `placement: nil` (all mailboxes on that account).
    case thisAccount

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .thisMailbox: return "This mailbox"
        case .thisAccount: return "This account · all mailboxes"
        }
    }

    public func placement(forAskPlacement askPlacement: String) -> String? {
        switch self {
        case .thisMailbox: return askPlacement
        case .thisAccount: return nil
        }
    }
}

/// Rule save hooks for the Ask rule editor (prompting agent only).
public struct ConditionalAccessAskRuleSupport {
    public let allRules: () -> [GrantRule]
    public let nextNick: () -> String
    public let messageProbe: IndexedMessage
    /// Persists the rule and enables it for the prompting agent at `placement`
    /// (`nil` = account-wide).
    public let onSave: (GrantRule, String?) -> Void

    public init(
        allRules: @escaping () -> [GrantRule],
        nextNick: @escaping () -> String,
        messageProbe: IndexedMessage,
        onSave: @escaping (GrantRule, String?) -> Void
    ) {
        self.allRules = allRules
        self.nextNick = nextNick
        self.messageProbe = messageProbe
        self.onSave = onSave
    }
}

enum AskEnvelopePick: String, Hashable, CaseIterable {
    case subject
    case from
}

enum AskRuleEditorIntent: String, CaseIterable, Identifiable {
    case newRule = "New"
    case existing = "Existing"

    var id: String { rawValue }
}

/// Shared draft for variant G: picks + right-pane editor + commit on Allow/Block.
@MainActor
final class ConditionalAccessAskRuleDraft: ObservableObject {
    @Published var picked: Set<AskEnvelopePick> = []
    @Published var detailOpen = false
    @Published var intent: AskRuleEditorIntent = .newRule
    @Published var selectedRuleID: String?

    @Published var ruleID = ""
    @Published var name = ""
    @Published var nick = "A"
    @Published var polarity: RulePolarity = .pass
    @Published var polarityTouched = false
    @Published var polarityOpen = false
    @Published var betweenJoin: JoinOp = .and
    @Published var fromRules: [MatchRule] = []
    @Published var subjectRules: [MatchRule] = []
    @Published var whenEnabled = false
    @Published var whenAfter = ""
    @Published var whenBefore = ""
    @Published var whenJoin: JoinOp = .and
    @Published var fields: GrantFields = .none
    @Published var enableScope: AskRuleEnableScope = .thisMailbox
    @Published var fromDraftMode: MatchMode = .exact
    @Published var fromDraftValue = ""
    @Published var subjectDraftMode: MatchMode = .exact
    @Published var subjectDraftValue = ""

    var isArmed: Bool { !picked.isEmpty }

    var fateLabel: String {
        intent == .existing ? "+ update rule" : "+ add rule"
    }

    func reset(for context: ConditionalAccessPromptContext, support: ConditionalAccessAskRuleSupport) {
        picked = []
        detailOpen = false
        intent = .newRule
        selectedRuleID = nil
        polarityTouched = false
        polarityOpen = false
        enableScope = .thisMailbox
        bootstrapNewRule(context: context, support: support)
    }

    func togglePick(
        _ key: AskEnvelopePick,
        context: ConditionalAccessPromptContext,
        support: ConditionalAccessAskRuleSupport
    ) {
        if picked.contains(key) {
            picked.remove(key)
            applyPick(key, on: false, context: context)
        } else {
            picked.insert(key)
            applyPick(key, on: true, context: context)
            detailOpen = true
        }
        syncAfterPicks(context: context, support: support)
    }

    func setDetailOpen(_ open: Bool, context: ConditionalAccessPromptContext) {
        detailOpen = open
        if open {
            prefillFromPicks(context: context)
        }
    }

    func chooseIntent(
        _ next: AskRuleEditorIntent,
        context: ConditionalAccessPromptContext,
        support: ConditionalAccessAskRuleSupport
    ) {
        intent = next
        switch next {
        case .newRule:
            bootstrapNewRule(context: context, support: support)
            prefillFromPicks(context: context)
        case .existing:
            loadExistingSelection(context: context, support: support)
            prefillFromPicks(context: context)
        }
        if isArmed {
            detailOpen = true
        }
    }

    /// Builds and persists the rule when armed. Returns false when nothing to write.
    @discardableResult
    func commit(
        decision: ConditionalAccessDecision,
        context: ConditionalAccessPromptContext,
        support: ConditionalAccessAskRuleSupport
    ) -> Bool {
        guard isArmed else { return false }
        let polarity = resolveCommitPolarity(decision: decision, support: support)
        let fromRules = withDraft(fromRules, mode: fromDraftMode, value: fromDraftValue)
        let subjectRules = withDraft(subjectRules, mode: subjectDraftMode, value: subjectDraftValue)
        let whenCommitted = whenEnabled
            && (
                !whenAfter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !whenBefore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
        guard !fromRules.isEmpty || !subjectRules.isEmpty || whenCommitted else { return false }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let when: RuleWhen? = whenEnabled
            ? RuleWhen(
                after: whenAfter.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                before: whenBefore.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
            : nil

        if intent == .existing {
            guard let current = support.allRules().first(where: { $0.id == selectedRuleID ?? ruleID }) else {
                return false
            }
            let rule = GrantRule(
                id: current.id,
                name: trimmedName.isEmpty ? current.name : trimmedName,
                nick: nick.isEmpty ? current.nick : nick,
                polarity: polarity,
                fromRules: fromRules,
                subjectRules: subjectRules,
                betweenJoin: betweenJoin,
                when: when,
                whenJoin: whenJoin,
                fields: detailOpen ? fields : current.fields
            )
            support.onSave(rule, enableScope.placement(forAskPlacement: context.placement))
            return true
        }

        let rule = GrantRule(
            id: ruleID.isEmpty ? "rule-\(UUID().uuidString.prefix(8))" : ruleID,
            name: trimmedName.isEmpty ? "From this ask" : trimmedName,
            nick: nick.isEmpty ? support.nextNick() : nick,
            polarity: polarity,
            fromRules: fromRules,
            subjectRules: subjectRules,
            betweenJoin: betweenJoin,
            when: when,
            whenJoin: whenJoin,
            fields: fields
        )
        support.onSave(rule, enableScope.placement(forAskPlacement: context.placement))
        return true
    }

    func bootstrapNewRule(context: ConditionalAccessPromptContext, support: ConditionalAccessAskRuleSupport) {
        ruleID = "rule-\(UUID().uuidString.prefix(8))"
        polarity = .pass
        polarityTouched = false
        name = "From this ask"
        nick = support.nextNick()
        betweenJoin = .and
        fromRules = []
        subjectRules = []
        whenEnabled = false
        whenAfter = ""
        whenBefore = ""
        whenJoin = .and
        fields = Self.defaultFields(for: context.requestedFields, polarity: .pass)
        enableScope = .thisMailbox
        fromDraftMode = .exact
        fromDraftValue = ""
        subjectDraftMode = .exact
        subjectDraftValue = ""
        selectedRuleID = nil
        prefillFromPicks(context: context)
    }

    func load(_ rule: GrantRule, context: ConditionalAccessPromptContext) {
        ruleID = rule.id
        selectedRuleID = rule.id
        name = rule.name
        nick = rule.nick
        polarity = rule.polarity
        polarityTouched = false
        betweenJoin = rule.betweenJoin
        fromRules = rule.fromRules
        subjectRules = rule.subjectRules
        whenEnabled = rule.when != nil
        whenAfter = rule.when?.after ?? ""
        whenBefore = rule.when?.before ?? ""
        whenJoin = rule.whenJoin
        fields = rule.fields
        prefillFromPicks(context: context)
    }

    private func syncAfterPicks(
        context: ConditionalAccessPromptContext,
        support: ConditionalAccessAskRuleSupport
    ) {
        prefillFromPicks(context: context)
        if picked.isEmpty {
            detailOpen = false
            intent = .newRule
            bootstrapNewRule(context: context, support: support)
        }
    }

    private func applyPick(_ key: AskEnvelopePick, on: Bool, context: ConditionalAccessPromptContext) {
        switch key {
        case .from:
            if on {
                fromDraftMode = .exact
                fromDraftValue = Grant.normalizeAddress(context.envelope.from)
            } else {
                fromDraftValue = ""
            }
        case .subject:
            if on {
                subjectDraftMode = .exact
                subjectDraftValue = context.envelope.subject
            } else {
                subjectDraftValue = ""
            }
        }
    }

    func prefillFromPicks(context: ConditionalAccessPromptContext) {
        if picked.contains(.from) {
            if fromDraftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                fromDraftMode = .exact
                fromDraftValue = Grant.normalizeAddress(context.envelope.from)
            }
        } else {
            fromDraftValue = ""
        }
        if picked.contains(.subject) {
            if subjectDraftValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                subjectDraftMode = .exact
                subjectDraftValue = context.envelope.subject
            }
        } else {
            subjectDraftValue = ""
        }
    }

    private func loadExistingSelection(
        context: ConditionalAccessPromptContext,
        support: ConditionalAccessAskRuleSupport
    ) {
        if let id = selectedRuleID, let rule = support.allRules().first(where: { $0.id == id }) {
            load(rule, context: context)
            return
        }
        if let first = sortedExistingRules(support: support).first {
            load(first, context: context)
        }
    }

    func sortedExistingRules(support: ConditionalAccessAskRuleSupport) -> [GrantRule] {
        let all = support.allRules()
        let probe = support.messageProbe
        return all.sorted { lhs, rhs in
            let leftHit = RuleEngine.matchesMatchersOnly(lhs, message: probe)
            let rightHit = RuleEngine.matchesMatchersOnly(rhs, message: probe)
            if leftHit != rightHit { return leftHit && !rightHit }
            return lhs.nick < rhs.nick
        }
    }

    private func resolveCommitPolarity(
        decision: ConditionalAccessDecision,
        support: ConditionalAccessAskRuleSupport
    ) -> RulePolarity {
        if polarityTouched { return polarity }
        if intent == .existing {
            if let current = support.allRules().first(where: { $0.id == selectedRuleID ?? ruleID }) {
                return current.polarity
            }
            return polarity
        }
        return decision == .allow ? .pass : .block
    }

    private func withDraft(_ list: [MatchRule], mode: MatchMode, value: String) -> [MatchRule] {
        var next = list
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return next }
        if !next.contains(where: { $0.mode == mode && $0.value == trimmed }) {
            next.append(MatchRule(value: trimmed, mode: mode))
        }
        return next
    }

    /// Pass reveals / Block withholds: requested Ask labels start On in the overlay mask.
    /// Attachment content requires names On as the `GrantFields` carrier bit (init strips
    /// content when names are Off) — same coupling Grant Desk applies via reconcile.
    nonisolated static func defaultFields(for requested: [String], polarity: RulePolarity) -> GrantFields {
        _ = polarity
        func mode(_ label: String) -> FieldAccessMode {
            requested.contains(label) ? .on : .off
        }
        let wantsContent = requested.contains("Attachment content")
        let namesOn = requested.contains("Attachment names") || wantsContent
        return GrantFields(
            subjectMode: mode("Subject"),
            fromMode: mode("From"),
            toMode: mode("To"),
            ccMode: mode("Cc"),
            dateMode: mode("Date"),
            bodyMode: mode("Body"),
            attachmentMetadataMode: namesOn ? .on : .off,
            attachmentContentMode: wantsContent ? .on : .off
        )
    }

    static func defaultWhenAfter() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static let nicks = (65...90).compactMap { UnicodeScalar($0).map(String.init) }
}

/// Variant G: right-pane rule editor (no in-panel Save; commit via Allow/Block).
struct ConditionalAccessAskRulePanel: View {
    let context: ConditionalAccessPromptContext
    let support: ConditionalAccessAskRuleSupport
    @ObservedObject var draft: ConditionalAccessAskRuleDraft
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Edit rule")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                AskFlushGhostButton(title: "Close", action: onClose)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.35)

            ScrollView {
                editorBody
                    .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: draft.polarity) { _, next in
            guard draft.intent == .newRule else { return }
            draft.fields = ConditionalAccessAskRuleDraft.defaultFields(
                for: context.requestedFields,
                polarity: next
            )
        }
    }

    private var editorBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            intentSwitch
            if draft.intent == .existing {
                existingPicker
            } else {
                Text("Name + Nick on one row · Value boxes save with Allow or Block when not empty")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                identityRow
            }
            polarityFold
            if draft.intent == .existing {
                identityRow
            }
            fromMatcherBlock
            betweenRow(label: "Between From and Subject", join: $draft.betweenJoin)
            subjectMatcherBlock
            betweenRow(label: "Between matchers and When", join: $draft.whenJoin)
            whenSection
            fieldOverlaySection
            enableOnSection
            Text(
                draft.intent == .existing
                    ? "Allow or Block updates this rule. Pass or Block stays as on the original unless you override it."
                    : "Allow or Block writes this rule and sets Pass or Block."
            )
            .font(.caption)
            .foregroundStyle(.tertiary)
            if draft.isArmed {
                pickedSummary
            }
        }
    }

    private var intentSwitch: some View {
        Picker("Rule intent", selection: Binding(
            get: { draft.intent },
            set: { draft.chooseIntent($0, context: context, support: support) }
        )) {
            ForEach(AskRuleEditorIntent.allCases) { item in
                Text(item.rawValue).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var existingPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shared rules")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            let rules = draft.sortedExistingRules(support: support)
            if rules.isEmpty {
                Text("No rules yet — use New to create one.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(rules) { rule in
                            let selected = draft.selectedRuleID == rule.id
                            let likely = RuleEngine.matchesMatchersOnly(rule, message: support.messageProbe)
                            Button {
                                draft.load(rule, context: context)
                            } label: {
                                HStack(spacing: 8) {
                                    RuleNickChip(nick: rule.nick, polarity: rule.polarity)
                                    Text(rule.name)
                                        .font(.caption.weight(selected ? .semibold : .regular))
                                        .lineLimit(1)
                                    if likely {
                                        Text("likely")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    selected ? Color.accentColor.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 120)
            }
        }
    }

    private var polarityFold: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    draft.polarityOpen.toggle()
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(polarityFoldLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(polarityFoldSub)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: draft.polarityOpen ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if draft.polarityOpen {
                HStack(spacing: 6) {
                    polarityButton(.pass, title: "Pass", detail: "Green-light fields on match")
                    polarityButton(.block, title: "Block", detail: "Withhold fields on match")
                }
            }
        }
    }

    private var polarityFoldLabel: String {
        if draft.polarityTouched {
            return draft.polarity == .pass
                ? "Pass, unless you change it"
                : "Block, unless you change it"
        }
        if draft.intent == .existing {
            return draft.polarity == .pass ? "Keeps Pass" : "Keeps Block"
        }
        return "Allow or Block sets Pass or Block"
    }

    private var polarityFoldSub: String {
        if draft.polarityOpen {
            return draft.intent == .existing
                ? "Pick one to override the original rule type"
                : "Pick one to override the decision buttons"
        }
        return draft.intent == .existing
            ? "Open only if this rule should change Pass or Block"
            : "Open only if this rule should not follow the button"
    }

    private func polarityHighlight(_ value: RulePolarity) -> Bool {
        if draft.polarityTouched { return draft.polarity == value }
        if draft.intent == .existing { return draft.polarity == value }
        return false
    }

    private func polarityButton(_ value: RulePolarity, title: String, detail: String) -> some View {
        let on = polarityHighlight(value)
        return Button {
            draft.polarity = value
            draft.polarityTouched = true
            draft.polarityOpen = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: value == .pass ? "checkmark.circle" : "xmark.circle")
                        .font(.system(size: 12, weight: .bold))
                    Text(title)
                        .font(.caption.weight(.bold))
                }
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .foregroundStyle(
                on
                    ? (value == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed)
                    : Color.primary
            )
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        on
                            ? (value == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed).opacity(0.12)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        on
                            ? (value == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed)
                            : Color.secondary.opacity(0.25),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var identityRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(draft.polarity == .pass ? "Pass name" : "Block name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Chip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Chip", selection: $draft.nick) {
                    ForEach(ConditionalAccessAskRuleDraft.nicks, id: \.self) { letter in
                        Text(letter).tag(letter)
                    }
                }
                .labelsHidden()
                .frame(width: 56)
            }
        }
    }

    private var fromMatcherBlock: some View {
        matcherBlock(
            title: "From",
            systemImage: "envelope",
            rules: $draft.fromRules,
            draftMode: $draft.fromDraftMode,
            draftValue: $draft.fromDraftValue
        )
    }

    private var subjectMatcherBlock: some View {
        matcherBlock(
            title: "Subject",
            systemImage: "text.alignleft",
            rules: $draft.subjectRules,
            draftMode: $draft.subjectDraftMode,
            draftValue: $draft.subjectDraftValue
        )
    }

    private func betweenRow(label: String, join: Binding<JoinOp>) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("Join")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                AskFlushSegmentButton(title: "AND", isOn: join.wrappedValue == .and) {
                    join.wrappedValue = .and
                }
                AskFlushSegmentButton(title: "OR", isOn: join.wrappedValue == .or) {
                    join.wrappedValue = .or
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("When")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("(optional time window)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer(minLength: 8)
                Toggle("", isOn: $draft.whenEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: draft.whenEnabled) { _, on in
                        if on, draft.whenAfter.isEmpty, draft.whenBefore.isEmpty {
                            draft.whenAfter = ConditionalAccessAskRuleDraft.defaultWhenAfter()
                        }
                    }
            }
            if draft.whenEnabled {
                HStack(spacing: 8) {
                    Text("After")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("YYYY-MM-DD", text: $draft.whenAfter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Text("Before")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("YYYY-MM-DD", text: $draft.whenBefore)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
        )
    }

    private var fieldOverlaySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(draft.polarity == .pass ? "Reveal + fields" : "Withhold − fields")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            GrantFieldBadgeRow(fields: draft.fields, interactive: true, showOff: true) { modeKeyPath in
                let current = draft.fields[keyPath: modeKeyPath]
                draft.fields[keyPath: modeKeyPath] = current == .on ? .off : .on
                draft.fields.reconcileAttachmentModes(changed: modeKeyPath)
            }
        }
    }

    private var enableOnSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Enable on")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                ForEach(AskRuleEnableScope.allCases) { scope in
                    let on = draft.enableScope == scope
                    Button {
                        draft.enableScope = scope
                    } label: {
                        Text(scope.title)
                            .font(.caption.weight(on ? .semibold : .regular))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(
                                on ? Color.accentColor.opacity(0.12) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(
                                        on ? Color.accentColor : Color.secondary.opacity(0.25),
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(enableOnCaption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
        )
    }

    private var enableOnCaption: String {
        switch draft.enableScope {
        case .thisMailbox:
            return "Attaches for this agent on \(context.placement) only."
        case .thisAccount:
            return "Attaches for this agent on every mailbox of this account."
        }
    }

    private var pickedSummary: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(draft.intent == .existing ? "Update rule" : "New rule")
                .font(.caption.weight(.semibold))
            Text(pickedSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                draft.intent == .existing
                    ? "Matchers already on the rule stay. A value box is saved too when it is not empty."
                    : "Value boxes that still have text are saved with Allow or Block. An empty box is left out."
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private var pickedSummaryText: String {
        var parts: [String] = []
        if draft.picked.contains(.subject) {
            parts.append("Subject is \(context.envelope.subject)")
        }
        if draft.picked.contains(.from) {
            parts.append("From is \(Grant.normalizeAddress(context.envelope.from))")
        }
        return parts.joined(separator: " · ")
    }

    private func matcherBlock(
        title: String,
        systemImage: String,
        rules: Binding<[MatchRule]>,
        draftMode: Binding<MatchMode>,
        draftValue: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            AskRuleMatchTags(rules: rules.wrappedValue) { index in
                var next = rules.wrappedValue
                next.remove(at: index)
                rules.wrappedValue = next
            }
            HStack(spacing: 6) {
                Picker("Mode", selection: draftMode) {
                    Text("contains").tag(MatchMode.contains)
                    Text("starts").tag(MatchMode.starts)
                    Text("ends").tag(MatchMode.ends)
                    Text("exact").tag(MatchMode.exact)
                }
                .labelsHidden()
                .frame(width: 100)
                TextField("Value", text: draftValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addRule(rules: rules, mode: draftMode, value: draftValue) }
                Button("Add") {
                    addRule(rules: rules, mode: draftMode, value: draftValue)
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
        )
    }

    private func addRule(
        rules: Binding<[MatchRule]>,
        mode: Binding<MatchMode>,
        value: Binding<String>
    ) {
        let trimmed = value.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        rules.wrappedValue.append(MatchRule(value: trimmed, mode: mode.wrappedValue))
        value.wrappedValue = ""
    }
}

private struct AskRuleMatchTags: View {
    let rules: [MatchRule]
    var onRemove: (Int) -> Void

    var body: some View {
        if rules.isEmpty {
            Text("No rules yet")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                    HStack(alignment: .top, spacing: 4) {
                        Text(rule.mode.rawValue.uppercased())
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary, in: Capsule())
                            .padding(.top, 2)
                        Text(rule.value)
                            .font(.caption.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button {
                            onRemove(index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 5)
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 6)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
