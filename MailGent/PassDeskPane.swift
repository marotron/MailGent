import MailStore
import SwiftUI

/// Passes tab: definitions list + editor (locked proto layout).
struct PassDeskPane: View {
    @Bindable var session: CompanionSession
    @Binding var selectedPassID: String?
    var isEditing: Bool

    private var definitions: [Pass] { session.agents.passDefinitions }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            passList
                .frame(width: 280, alignment: .top)
            ScrollView {
                passEditor
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.bottom, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var passList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Passes")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if definitions.isEmpty {
                Text("No passes yet. Create one to green-light fields on match.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(definitions) { pass in
                            passRow(pass)
                        }
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            Button {
                guard isEditing else { return }
                let draft = session.agents.createPassDraft()
                session.agents.upsertPass(draft)
                selectedPassID = draft.id
            } label: {
                Text("+ New pass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!isEditing)
        }
    }

    private func passRow(_ pass: Pass) -> some View {
        let on = selectedPassID == pass.id
        return Button {
            selectedPassID = pass.id
        } label: {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 2) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text(pass.nick)
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255))
                .padding(.horizontal, 6)
                .frame(height: 20)
                .background(
                    Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255).opacity(0.12),
                    in: Capsule()
                )
                .overlay(
                    Capsule().strokeBorder(
                        Color(red: 143 / 255, green: 209 / 255, blue: 160 / 255),
                        lineWidth: 1
                    )
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(pass.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                    HStack(alignment: .center, spacing: 4) {
                        PassMatchSummary(pass: pass)
                        if !pass.fromRules.isEmpty || !pass.subjectRules.isEmpty {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.green)
                        }
                        Spacer(minLength: 4)
                        GrantFieldBadgeRow(
                            fields: pass.fields,
                            interactive: false,
                            showOff: false,
                            labelMode: .icon
                        )
                    }
                    HStack(alignment: .center, spacing: 4) {
                        Text(usageLabel(pass.id))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer(minLength: 4)
                        passAgentGlyphs(pass)
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

    private var passEditor: some View {
        Group {
            if let pass = selectedPass ?? definitions.first {
                PassEditorForm(
                    pass: pass,
                    isEditing: isEditing,
                    knownAgents: session.agents.knownAgentsForPasses,
                    onChange: { session.agents.upsertPass($0) },
                    onDelete: {
                        session.agents.deletePass(id: pass.id)
                        selectedPassID = session.agents.passDefinitions.first?.id
                    }
                )
            } else {
                ContentUnavailableView(
                    "Select a pass",
                    systemImage: "checkmark.circle",
                    description: Text("Definitions live here. Attach them on Scope as green chips.")
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

    private var selectedPass: Pass? {
        guard let selectedPassID else { return nil }
        return definitions.first { $0.id == selectedPassID }
    }

    private func usageLabel(_ passID: String) -> String {
        let n = session.agents.passUsageCount(passID)
        if n == 0 { return "Not used yet" }
        return n == 1 ? "Used on 1 placement" : "Used on \(n) placements"
    }

    @ViewBuilder
    private func passAgentGlyphs(_ pass: Pass) -> some View {
        if pass.agentIDs.isEmpty {
            Image(systemName: "cpu")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .opacity(0.35)
        } else {
            HStack(spacing: 2) {
                ForEach(pass.agentIDs, id: \.self) { agentID in
                    let name = session.agents.knownAgentsForPasses
                        .first { $0.id == agentID }?.name ?? agentID
                    AgentGlyph(name: name, size: 12)
                }
            }
        }
    }
}

private struct PassMatchSummary: View {
    let pass: Pass

    var body: some View {
        HStack(spacing: 3) {
            if !pass.fromRules.isEmpty {
                ruleBits(pass.fromRules, systemImage: "envelope")
            }
            if !pass.fromRules.isEmpty, !pass.subjectRules.isEmpty {
                Text(pass.betweenJoin == .and ? "AND" : "OR")
                    .font(.system(size: 8, weight: .bold))
            }
            if !pass.subjectRules.isEmpty {
                ruleBits(pass.subjectRules, systemImage: "text.alignleft")
            }
        }
        .lineLimit(1)
    }

    private func ruleBits(_ rules: [MatchRule], systemImage: String) -> some View {
        HStack(spacing: 2) {
            Image(systemName: systemImage)
                .font(.system(size: 8))
            Text(rules.map(\.value).joined(separator: " · "))
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }
}

private struct PassEditorForm: View {
    let pass: Pass
    var isEditing: Bool
    var knownAgents: [(id: String, name: String)]
    var onChange: (Pass) -> Void
    var onDelete: () -> Void

    @State private var name: String = ""
    @State private var nick: String = "A"
    @State private var betweenJoin: JoinOp = .and
    @State private var fromRules: [MatchRule] = []
    @State private var subjectRules: [MatchRule] = []
    @State private var fields: GrantFields = GrantFields(envelope: false, body: true)
    @State private var agentIDs: [String] = []
    @State private var fromDraftMode: MatchMode = .contains
    @State private var fromDraftValue = ""
    @State private var subjectDraftMode: MatchMode = .contains
    @State private var subjectDraftValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                betweenRow
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
            VStack(alignment: .leading, spacing: 6) {
                Text("Green-light fields")
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
            }
            agentsRow
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

    private var agentsRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agents")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if knownAgents.isEmpty {
                Text("No agent paired yet.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(knownAgents, id: \.id) { agent in
                    Toggle(isOn: Binding(
                        get: { agentIDs.contains(agent.id) },
                        set: { on in
                            if on {
                                if !agentIDs.contains(agent.id) { agentIDs.append(agent.id) }
                            } else {
                                agentIDs.removeAll { $0 == agent.id }
                            }
                            commit()
                        }
                    )) {
                        HStack(spacing: 6) {
                            AgentGlyph(name: agent.name, size: 14)
                            Text(agent.name)
                                .font(.caption)
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(!isEditing)
                }
            }
        }
    }

    private var identityRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Pass name", text: $name)
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

    private var betweenRow: some View {
        Group {
            if isEditing {
                betweenRowEditing
            } else {
                betweenRowViewOnly
            }
        }
    }

    private var betweenRowViewOnly: some View {
        PassJoinBadge(join: betweenJoin)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var betweenRowEditing: some View {
        HStack(spacing: 8) {
            Text("Between From and Subject")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("Join")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                joinButton("AND", op: .and)
                joinButton("OR", op: .or)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func joinButton(_ title: String, op: JoinOp) -> some View {
        if betweenJoin == op {
            Button(title) {
                betweenJoin = op
                commit()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!isEditing)
        } else {
            Button(title) {
                betweenJoin = op
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

    private func load(_ pass: Pass) {
        name = pass.name
        nick = pass.nick
        betweenJoin = pass.betweenJoin
        fromRules = pass.fromRules
        subjectRules = pass.subjectRules
        fields = pass.fields
        agentIDs = pass.agentIDs
    }

    private func commit() {
        guard isEditing else { return }
        var next = pass
        next.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? pass.name : name
        next.nick = nick
        next.betweenJoin = betweenJoin
        next.fromRules = fromRules
        next.subjectRules = subjectRules
        next.fields = fields
        next.agentIDs = agentIDs
        onChange(next)
    }

    private static let nicks = (65...90).compactMap { UnicodeScalar($0).map(String.init) }
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
            HStack(spacing: 6) {
                ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
                    HStack(spacing: 4) {
                        Text(rule.mode.rawValue.uppercased())
                            .font(.system(size: 7, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary, in: Capsule())
                        Text(rule.value)
                            .font(.caption.weight(.semibold))
                        if isEditing {
                            Button {
                                onRemove(index)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 3)
                    .padding(.trailing, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                }
            }
        }
    }
}

/// Per-pass toggle chips (`✓ A` / `✓ B`). Green when attached, grey when not. Click to toggle.
struct PassToggleChips: View {
    enum Density {
        /// Scope rows — same height as field badges.
        case compact
        /// Access editor — same size as Envelope / Content chips.
        case roomy
    }

    @Bindable var session: CompanionSession
    let accountID: String
    let placement: String?
    var isEditing: Bool
    var density: Density = .compact

    private static let passGreen = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255)

    private var definitions: [Pass] {
        session.agents.passDefinitions.sorted { $0.nick < $1.nick }
    }

    private var attachedIDs: Set<String> {
        Set(session.agents.enabledPasses(accountID: accountID, placement: placement).map(\.id))
    }

    var body: some View {
        if definitions.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: density == .compact ? 3 : 6) {
                ForEach(definitions) { pass in
                    let on = attachedIDs.contains(pass.id)
                    Button {
                        session.agents.togglePassEnabled(
                            passID: pass.id,
                            accountID: accountID,
                            placement: placement
                        )
                    } label: {
                        chipLabel(nick: pass.nick, isOn: on)
                    }
                    .buttonStyle(.plain)
                    .disabled(!isEditing)
                    .help(pass.name)
                    .accessibilityLabel("Pass \(pass.nick), \(pass.name)")
                    .accessibilityAddTraits(on ? [.isSelected] : [])
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    @ViewBuilder
    private func chipLabel(nick: String, isOn: Bool) -> some View {
        switch density {
        case .compact:
            Text("✓\(nick)")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(isOn ? Self.passGreen : Color.secondary.opacity(0.55))
                .tracking(0.4)
                .padding(.horizontal, 5)
                .frame(height: 14)
                .background(
                    Capsule().fill(
                        isOn ? Self.passGreen.opacity(0.12) : Color.secondary.opacity(0.08)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn
                            ? Color(red: 143 / 255, green: 209 / 255, blue: 160 / 255)
                            : Color.secondary.opacity(0.2),
                        lineWidth: 0.5
                    )
                )
        case .roomy:
            Text("✓ \(nick)")
                .font(.caption)
                .foregroundStyle(isOn ? Self.passGreen : Color.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(
                        isOn ? Self.passGreen.opacity(0.12) : Color.secondary.opacity(0.08)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        isOn ? Self.passGreen.opacity(0.45) : Color.secondary.opacity(0.25),
                        lineWidth: isOn ? 1.5 : 0.5
                    )
                )
        }
    }
}

/// View-mode join operator between From and Subject rule blocks.
private struct PassJoinBadge: View {
    let join: JoinOp

    var body: some View {
        Text(join == .and ? "AND" : "OR")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary, in: Capsule())
            .accessibilityLabel("Join From and Subject with \(join == .and ? "AND" : "OR")")
    }
}

#Preview("Rule tags") {
    FlowRuleTags(
        rules: [
            MatchRule(value: "invoice", mode: .contains),
            MatchRule(value: "Re:", mode: .starts),
            MatchRule(value: ".pdf", mode: .ends),
            MatchRule(value: "URGENT", mode: .exact),
        ],
        isEditing: true,
        onRemove: { _ in }
    )
    .padding()
    .frame(width: 520)
}

#Preview("Join AND / OR (view)") {
    VStack(alignment: .leading, spacing: 16) {
        Text("AND")
            .font(.caption)
            .foregroundStyle(.secondary)
        PassJoinBadge(join: .and)
            .frame(maxWidth: .infinity, alignment: .center)

        Text("OR")
            .font(.caption)
            .foregroundStyle(.secondary)
        PassJoinBadge(join: .or)
            .frame(maxWidth: .infinity, alignment: .center)
    }
    .padding()
    .frame(width: 320)
}
