import MailStore
import SwiftUI

/// Shared Rules tab: Pass (green-light) + Block (withhold) definitions with optional When window.
struct PassDeskPane: View {
    @Bindable var session: CompanionSession
    @Binding var selectedPassID: String?
    var isEditing: Bool

    @State private var listFilter: ListFilter = .all

    private enum ListFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case pass = "Passes"
        case block = "Blocks"
        var id: String { rawValue }
    }

    private var definitions: [GrantRule] { session.agents.ruleDefinitions }

    private var visibleDefinitions: [GrantRule] {
        switch listFilter {
        case .all: return definitions
        case .pass: return definitions.filter { $0.polarity == .pass }
        case .block: return definitions.filter { $0.polarity == .block }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rulesList
                .frame(width: 280, alignment: .top)
            ScrollView {
                ruleEditor
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var rulesList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Rules")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker("Filter", selection: $listFilter) {
                ForEach(ListFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            if visibleDefinitions.isEmpty {
                Text(emptyListCopy)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(visibleDefinitions) { pass in
                            ruleRow(pass)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }

            HStack(spacing: 6) {
                Button {
                    guard isEditing else { return }
                    addRule(polarity: .pass)
                } label: {
                    Text("+ Pass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(RuleMarkStyle.passGreen)
                .controlSize(.small)
                .disabled(!isEditing)

                Button {
                    guard isEditing else { return }
                    addRule(polarity: .block)
                } label: {
                    Text("+ Block")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(RuleMarkStyle.blockRed)
                .controlSize(.small)
                .disabled(!isEditing)
            }
        }
    }

    private var emptyListCopy: String {
        switch listFilter {
        case .all:
            return "No rules yet. Add a Pass to green-light fields, or a Block to withhold them."
        case .pass:
            return "No passes yet."
        case .block:
            return "No blocks yet."
        }
    }

    private func addRule(polarity: RulePolarity) {
        let draft = session.agents.createRuleDraft(polarity: polarity)
        session.agents.upsertRule(draft)
        selectedPassID = draft.id
        listFilter = .all
    }

    private func ruleRow(_ pass: GrantRule) -> some View {
        let on = selectedPassID == pass.id
        return Button {
            selectedPassID = pass.id
        } label: {
            HStack(alignment: .top, spacing: 8) {
                RuleNickChip(nick: pass.nick, polarity: pass.polarity)
                VStack(alignment: .leading, spacing: 3) {
                    Text(pass.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    HStack(alignment: .top, spacing: 4) {
                        HStack(alignment: .top, spacing: 4) {
                            PassMatchSummary(pass: pass)
                            if hasMatchers(pass) {
                                Image(systemName: pass.polarity == .pass ? "arrow.right" : "minus")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(
                                        pass.polarity == .pass
                                            ? RuleMarkStyle.passGreen
                                            : RuleMarkStyle.blockRed
                                    )
                                    .padding(.top, 2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .layoutPriority(0)
                        GrantFieldBadgeRow(
                            fields: pass.fields,
                            interactive: false,
                            showOff: false,
                            labelMode: .icon
                        )
                        .fixedSize()
                    }
                    HStack(alignment: .center, spacing: 4) {
                        if pass.when != nil {
                            Text("When")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(Color.orange.opacity(0.9))
                        }
                        Text(usageLabel(pass.id))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Color.accentColor.opacity(0.12) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var ruleEditor: some View {
        Group {
            if let pass = selectedRule ?? definitions.first {
                PassEditorForm(
                    pass: pass,
                    isEditing: isEditing,
                    onChange: { session.agents.upsertRule($0) },
                    onDelete: {
                        session.agents.deleteRule(id: pass.id)
                        selectedPassID = session.agents.ruleDefinitions.first?.id
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a rule",
                    systemImage: "checklist",
                    description: Text("Pass grants denied fields on match; Block denies granted fields. Attach on Scope.")
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        }
        .onAppear {
            if selectedPassID == nil {
                selectedPassID = definitions.first?.id
            }
        }
        .onChange(of: definitions.map(\.id)) { _, ids in
            if let selectedPassID, !ids.contains(selectedPassID) {
                self.selectedPassID = ids.first
            }
        }
    }

    private var selectedRule: GrantRule? {
        guard let selectedPassID else { return nil }
        return definitions.first { $0.id == selectedPassID }
    }

    private func hasMatchers(_ pass: GrantRule) -> Bool {
        !pass.fromRules.isEmpty || !pass.subjectRules.isEmpty || pass.when != nil
    }

    private func usageLabel(_ ruleID: String) -> String {
        let n = session.agents.ruleUsageCount(ruleID)
        if n == 0 { return "Not used yet" }
        return n == 1 ? "Used on 1 placement" : "Used on \(n) placements"
    }
}

struct RuleNickChip: View {
    let nick: String
    let polarity: RulePolarity

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: polarity == .pass ? "checkmark.circle" : "xmark.circle")
                .font(.system(size: 10, weight: .bold))
            Text(nick)
                .font(.caption.weight(.bold))
        }
        .foregroundStyle(polarity == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(
            (polarity == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed).opacity(0.12),
            in: Capsule()
        )
        .overlay(
            Capsule().strokeBorder(
                polarity == .pass ? RuleMarkStyle.passBorder : RuleMarkStyle.blockBorder,
                lineWidth: 1
            )
        )
        .accessibilityLabel("\(polarity == .pass ? "Pass" : "Block") \(nick)")
    }
}

private struct PassMatchSummary: View {
    let pass: GrantRule

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !pass.fromRules.isEmpty {
                ruleLines(pass.fromRules, systemImage: "envelope")
            }
            if !pass.fromRules.isEmpty, !pass.subjectRules.isEmpty {
                Text(pass.betweenJoin == .and ? "AND" : "OR")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            if !pass.subjectRules.isEmpty {
                ruleLines(pass.subjectRules, systemImage: "text.alignleft")
            }
            if let when = pass.when {
                if !pass.fromRules.isEmpty || !pass.subjectRules.isEmpty {
                    Text(pass.whenJoin == .and ? "AND" : "OR")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                Text(whenSummary(when))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func whenSummary(_ when: RuleWhen) -> String {
        let after = when.after?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let before = when.before?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if after.isEmpty, before.isEmpty { return "When (open)" }
        if before.isEmpty { return "After \(after)" }
        if after.isEmpty { return "Before \(before)" }
        return "\(after) → \(before)"
    }

    private func ruleLines(_ rules: [MatchRule], systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(rules.enumerated()), id: \.offset) { _, rule in
                HStack(spacing: 2) {
                    Image(systemName: systemImage)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                    Text(rule.value)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private struct PassEditorForm: View {
    let pass: GrantRule
    var isEditing: Bool
    var onChange: (GrantRule) -> Void
    var onDelete: () -> Void

    @State private var name: String = ""
    @State private var nick: String = "A"
    @State private var polarity: RulePolarity = .pass
    @State private var betweenJoin: JoinOp = .and
    @State private var fromRules: [MatchRule] = []
    @State private var subjectRules: [MatchRule] = []
    @State private var whenEnabled = false
    @State private var whenAfter = ""
    @State private var whenBefore = ""
    @State private var whenJoin: JoinOp = .and
    @State private var fields: GrantFields = GrantFields(envelope: false, body: true)
    @State private var fromDraftMode: MatchMode = .contains
    @State private var fromDraftValue = ""
    @State private var subjectDraftMode: MatchMode = .contains
    @State private var subjectDraftValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isEditing {
                polarityPicker
            }
            identityRow
            if isEditing || !fromRules.isEmpty {
                ruleBlock(
                    title: "From",
                    systemImage: "envelope",
                    rules: $fromRules,
                    draftMode: $fromDraftMode,
                    draftValue: $fromDraftValue
                )
            }
            if isEditing || (!fromRules.isEmpty && !subjectRules.isEmpty) {
                betweenRow(label: "Between From and Subject", join: $betweenJoin)
            }
            if isEditing || !subjectRules.isEmpty {
                ruleBlock(
                    title: "Subject",
                    systemImage: "text.alignleft",
                    rules: $subjectRules,
                    draftMode: $subjectDraftMode,
                    draftValue: $subjectDraftValue
                )
            }
            if isEditing || whenEnabled {
                if isEditing || (!fromRules.isEmpty || !subjectRules.isEmpty) {
                    betweenRow(label: "Between matchers and When", join: $whenJoin)
                }
                whenSection
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(polarity == .pass ? "Reveal + fields" : "Withhold − fields")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                GrantFieldBadgeRow(
                    fields: fields,
                    interactive: isEditing,
                    showOff: isEditing
                ) { keyPath in
                    fields[keyPath: keyPath].toggle()
                    if keyPath == \.attachmentContent, fields.attachmentContent {
                        fields.attachmentMetadata = true
                    }
                    if keyPath == \.attachmentMetadata, !fields.attachmentMetadata {
                        fields.attachmentContent = false
                    }
                    commit()
                }
                Text(
                    polarity == .pass
                        ? "Grant overwrite: turn these fields on when match hits (only if Scope left them off). Mailbox must be Scope-allowed first."
                        : "Deny overwrite: turn these fields off when match hits (only if they would otherwise be on)."
                )
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
            HStack {
                Button("Delete", role: .destructive, action: onDelete)
                    .disabled(!isEditing)
                Spacer()
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .onAppear { load(pass) }
        .onChange(of: pass.id) { _, _ in load(pass) }
    }

    private var polarityPicker: some View {
        HStack(spacing: 6) {
            polarityButton(.pass, title: "Pass", detail: "Green-light fields on match")
            polarityButton(.block, title: "Block", detail: "Withhold fields on match")
        }
    }

    private func polarityButton(_ value: RulePolarity, title: String, detail: String) -> some View {
        let on = polarity == value
        return Button {
            polarity = value
            commit()
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
        .disabled(!isEditing)
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
                Toggle("", isOn: Binding(
                    get: { whenEnabled },
                    set: { on in
                        whenEnabled = on
                        if on, whenAfter.isEmpty, whenBefore.isEmpty {
                            whenAfter = Self.defaultWhenAfter()
                        }
                        commit()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isEditing)
            }
            if whenEnabled {
                HStack(spacing: 8) {
                    Text("After")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("YYYY-MM-DD", text: $whenAfter)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .disabled(!isEditing)
                        .onChange(of: whenAfter) { _, _ in commit() }
                    Text("Before")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("YYYY-MM-DD", text: $whenBefore)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .disabled(!isEditing)
                        .onChange(of: whenBefore) { _, _ in commit() }
                }
                Text("Joined to From/Subject with AND|OR above. Empty side = open-ended.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
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

    private var identityRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(polarity == .pass ? "Pass name" : "Block name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!isEditing)
                    .onSubmit { commit() }
                    .onChange(of: name) { _, _ in commit() }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Chip")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Chip", selection: $nick) {
                    ForEach(Self.nicks, id: \.self) { letter in
                        Text(letter).tag(letter)
                    }
                }
                .labelsHidden()
                .frame(width: 56)
                .disabled(!isEditing)
                .onChange(of: nick) { _, _ in commit() }
            }
        }
    }

    private func betweenRow(label: String, join: Binding<JoinOp>) -> some View {
        Group {
            if isEditing {
                HStack(spacing: 8) {
                    Text(label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text("Join")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        joinButton("AND", op: .and, join: join)
                        joinButton("OR", op: .or, join: join)
                    }
                    .controlSize(.small)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            } else {
                PassJoinBadge(join: join.wrappedValue)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }

    @ViewBuilder
    private func joinButton(_ title: String, op: JoinOp, join: Binding<JoinOp>) -> some View {
        if join.wrappedValue == op {
            Button(title) {
                join.wrappedValue = op
                commit()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEditing)
        } else {
            Button(title) {
                join.wrappedValue = op
                commit()
            }
            .buttonStyle(.bordered)
            .disabled(!isEditing)
        }
    }

    private func ruleBlock(
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
            FlowRuleTags(rules: rules.wrappedValue, isEditing: isEditing) { index in
                var next = rules.wrappedValue
                next.remove(at: index)
                rules.wrappedValue = next
                commit()
            }
            if isEditing {
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
        commit()
    }

    private func load(_ pass: GrantRule) {
        name = pass.name
        nick = pass.nick
        polarity = pass.polarity
        betweenJoin = pass.betweenJoin
        fromRules = pass.fromRules
        subjectRules = pass.subjectRules
        whenEnabled = pass.when != nil
        whenAfter = pass.when?.after ?? ""
        whenBefore = pass.when?.before ?? ""
        whenJoin = pass.whenJoin
        fields = pass.fields
    }

    private func commit() {
        guard isEditing else { return }
        var next = pass
        next.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? pass.name : name
        next.nick = nick
        next.polarity = polarity
        next.betweenJoin = betweenJoin
        next.fromRules = fromRules
        next.subjectRules = subjectRules
        if whenEnabled {
            next.when = RuleWhen(
                after: whenAfter.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
                before: whenBefore.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            )
        } else {
            next.when = nil
        }
        next.whenJoin = whenJoin
        next.fields = fields
        onChange(next)
    }

    private static func defaultWhenAfter() -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static let nicks = (65...90).compactMap { UnicodeScalar($0).map(String.init) }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private struct FlowRuleTags: View {
    let rules: [MatchRule]
    var isEditing: Bool
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
                            .padding(.vertical, 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if isEditing {
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
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 6)
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.accentColor.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Per-rule toggle chips on Scope. Pass = green check; Block = red x. Shared letter pool.
struct PassToggleChips: View {
    enum Density {
        case compact
        case roomy
    }

    @Bindable var session: CompanionSession
    let accountID: String
    let placement: String?
    var isEditing: Bool
    var density: Density = .compact

    private var definitions: [GrantRule] {
        session.agents.ruleDefinitions.sorted { $0.nick < $1.nick }
    }

    private var attachedIDs: Set<String> {
        Set(session.agents.enabledRules(accountID: accountID, placement: placement).map(\.id))
    }

    var body: some View {
        if definitions.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: density == .compact ? 3 : 6) {
                ForEach(definitions) { pass in
                    let on = attachedIDs.contains(pass.id)
                    Button {
                        session.agents.toggleRuleEnabled(
                            ruleID: pass.id,
                            accountID: accountID,
                            placement: placement
                        )
                    } label: {
                        chipLabel(pass: pass, isOn: on)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEditing)
                    .help(pass.name)
                    .accessibilityLabel("\(pass.polarity == .pass ? "Pass" : "Block") \(pass.nick), \(pass.name)")
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func chipLabel(pass: GrantRule, isOn: Bool) -> some View {
        let ink: Color = {
            guard isOn else { return Color.secondary.opacity(density == .compact ? 0.55 : 1) }
            return pass.polarity == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed
        }()
        let mark = pass.polarity == .pass ? "✓" : "✗"
        switch density {
        case .compact:
            Text("\(mark)\(pass.nick)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(ink)
                .tracking(0.4)
                .padding(.horizontal, 5)
                .frame(height: 14)
                .background(
                    Capsule().fill(
                        isOn ? ink.opacity(0.12) : Color.secondary.opacity(0.08)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn
                            ? (pass.polarity == .pass ? RuleMarkStyle.passBorder : RuleMarkStyle.blockBorder)
                            : Color.secondary.opacity(0.2),
                        lineWidth: 0.5
                    )
                )
        case .roomy:
            HStack(spacing: 3) {
                Image(systemName: pass.polarity == .pass ? "checkmark.circle" : "xmark.circle")
                    .font(.system(size: 10, weight: .bold))
                Text(pass.nick)
                    .font(.caption.weight(.bold))
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(
                    isOn ? ink.opacity(0.12) : Color.secondary.opacity(0.08)
                )
            )
            .overlay(
                Capsule().strokeBorder(
                    isOn ? ink.opacity(0.45) : Color.secondary.opacity(0.25),
                    lineWidth: isOn ? 1.5 : 0.5
                )
            )
        }
    }
}

private struct PassJoinBadge: View {
    let join: JoinOp

    var body: some View {
        Text(join == .and ? "AND" : "OR")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary, in: Capsule())
            .accessibilityLabel("Join with \(join == .and ? "AND" : "OR")")
    }
}

#Preview("Rule tags") {
    FlowRuleTags(
        rules: [
            MatchRule(value: "invoice", mode: .contains),
            MatchRule(value: "Re:", mode: .starts),
        ],
        isEditing: true,
        onRemove: { _ in }
    )
    .padding()
    .frame(width: 520)
}
