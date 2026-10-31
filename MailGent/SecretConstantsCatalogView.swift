import AppKit
import MailStore
import SwiftUI

/// Control Center catalog — proto C list|detail (approved).
struct SecretConstantsCatalogView: View {
    @Bindable var session: CompanionSession

    @AppStorage(MailGentPreferences.secretConstantsEnabledKey) private var secretConstantsEnabled = false
    @State private var selectedName: String?
    @State private var editing = false
    @State private var draft = DraftConstant()
    @State private var revealValue = false
    @State private var errorNote: String?

    private var agents: AgentBridge { session.agents }
    private var catalog: SecretConstantsCatalog {
        agents.secretConstantsCatalog
    }

    private var selected: SecretConstant? {
        guard let selectedName else { return nil }
        return catalog[selectedName]
    }

    var body: some View {
        VStack(spacing: 0) {
            if !secretConstantsEnabled {
                masterOffBanner
            }
            HStack(spacing: 0) {
                listPane
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 380)
                Divider()
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .opacity(secretConstantsEnabled ? 1 : 0.55)
            .allowsHitTesting(secretConstantsEnabled)
        }
        .frame(minWidth: 720, minHeight: 420)
        .onAppear {
            if selectedName == nil {
                selectedName = catalog.constants.first?.name
            }
        }
        .onChange(of: agents.secretConstantsRevision) { _, _ in
            if let selectedName, catalog[selectedName] == nil {
                self.selectedName = catalog.constants.first?.name
                editing = false
            }
        }
    }

    private var masterOffBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.secondary)
            Text("Secret constants are off. Enable them in Settings to edit or use placeholders.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Open Settings") {
                DetachedWindowHost.shared.showSettings(session: session)
            }
            .buttonStyle(.link)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            List(selection: $selectedName) {
                ForEach(catalog.constants) { constant in
                    listRow(constant)
                        .tag(constant.name)
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selectedName) { _, newValue in
                // List pick leaves edit/add. Clearing selection for Add must not
                // clobber `editing = true` set in `beginAdd` (same update cycle).
                guard newValue != nil else { return }
                editing = false
                revealValue = false
                errorNote = nil
            }

            Divider()
            Button {
                beginAdd()
            } label: {
                Label("Add constant", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.borderless)
            .padding(10)
            .disabled(!secretConstantsEnabled)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func listRow(_ constant: SecretConstant) -> some View {
        HStack(spacing: 8) {
            Text(constant.name)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(constant.label.isEmpty ? "—" : constant.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            agentGlyphCluster(constant.allowedAgentIDs)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func agentGlyphCluster(_ agentIDs: [String]) -> some View {
        let paired = agents.pairedAgents.filter { agentIDs.contains($0.id) }
        if paired.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 3) {
                ForEach(paired) { agent in
                    AgentGlyph(name: agent.name, size: 14)
                }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if editing {
            editDetail
        } else if let selected {
            viewDetail(selected)
        } else {
            ContentUnavailableView(
                "No constant selected",
                systemImage: "key.fill",
                description: Text("Choose a constant or add one.")
            )
        }
    }

    private func viewDetail(_ constant: SecretConstant) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(constant.name)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    Spacer()
                    Button("Edit") {
                        beginEdit(constant)
                    }
                    .disabled(!secretConstantsEnabled)
                }

                constantCard(constant, editable: false)

                tokenPreview(name: constant.name)

                allowedAgentsView(constant)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var editDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("name", text: $draft.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .disabled(draft.isExisting)

                if let errorNote {
                    Text(errorNote)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                GroupBox {
                    VStack(spacing: 10) {
                        labeled("Label") {
                            TextField("Label", text: $draft.label)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 280)
                        }
                        labeled("Hint") {
                            Picker("", selection: $draft.hint) {
                                Text("phone").tag(SecretConstantHint.phone)
                                Text("address").tag(SecretConstantHint.address)
                                Text("id").tag(SecretConstantHint.id)
                                Text("other").tag(SecretConstantHint.other)
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .fixedSize()
                        }
                        valueEditRow
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Constant")
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                tokenPreview(name: draft.name)

                allowedAgentsEdit

                HStack(spacing: 8) {
                    if draft.isExisting {
                        Button("Delete constant", role: .destructive) {
                            deleteSelected()
                        }
                    }
                    Spacer(minLength: 8)
                    Button("Cancel") {
                        editing = false
                        errorNote = nil
                    }
                    Button("Save") {
                        saveDraft()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!secretConstantsEnabled)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var valueEditRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            labeled("Value") {
                HStack(spacing: 6) {
                    Button(revealValue ? "Hide" : "Show") {
                        revealValue.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    Button {
                        draft.multiline.toggle()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .help(draft.multiline ? "Switch to single-line" : "Switch to multiline")
                    if !draft.multiline {
                        valueSingleLineField
                            .frame(minWidth: 160, idealWidth: 220, maxWidth: 280)
                    }
                }
            }
            if draft.multiline {
                TextEditor(text: $draft.value)
                    .font(.body.monospaced())
                    .frame(minHeight: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.12))
                    )
                    .opacity(revealValue ? 1 : 0.55)
                Text("Optional multiline for addresses and other long secrets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var valueSingleLineField: some View {
        if revealValue {
            TextField("Value", text: $draft.value)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospaced())
        } else {
            SecureField("Value", text: $draft.value)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func constantCard(_ constant: SecretConstant, editable: Bool) -> some View {
        GroupBox {
            VStack(spacing: 10) {
                labeled("Label") {
                    Text(constant.label.isEmpty ? "—" : constant.label)
                        .multilineTextAlignment(.trailing)
                }
                labeled("Hint") {
                    Text(constant.hint?.rawValue ?? "—")
                }
                labeled("Value") {
                    HStack(spacing: 6) {
                        Button(revealValue ? "Hide" : "Show") {
                            revealValue.toggle()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        Text(revealValue ? constant.value : String(repeating: "•", count: max(6, min(constant.value.count, 12))))
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                            .lineLimit(constant.multiline ? nil : 1)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Constant")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(editable ? 1 : 1)
    }

    private func tokenPreview(name: String) -> some View {
        let token = SecretConstantPlaceholders.isValidName(name)
            ? SecretConstantPlaceholders.token(for: name)
            : "[[mg:…]]"
        return GroupBox {
            HStack {
                Text(token)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(token, forType: .string)
                }
                .disabled(!SecretConstantPlaceholders.isValidName(name))
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Token preview")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func allowedAgentsView(_ constant: SecretConstant) -> some View {
        GroupBox {
            let allowed = agents.pairedAgents.filter { constant.allowedAgentIDs.contains($0.id) }
            if allowed.isEmpty {
                Text("No agents allowlisted")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(allowed) { agent in
                        HStack {
                            AgentGlyph(name: agent.name, size: 16)
                            Text(agent.name)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } label: {
            Text("Allowed agents")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var allowedAgentsEdit: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(agents.pairedAgents) { agent in
                    Toggle(isOn: Binding(
                        get: { draft.allowedAgentIDs.contains(agent.id) },
                        set: { on in
                            if on {
                                draft.allowedAgentIDs.insert(agent.id)
                            } else {
                                draft.allowedAgentIDs.remove(agent.id)
                            }
                        }
                    )) {
                        HStack {
                            AgentGlyph(name: agent.name, size: 16)
                            Text(agent.name)
                            Spacer(minLength: 0)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if agents.pairedAgents.isEmpty {
                    Text("Pair an agent in Control Center first.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Allowed agents")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Proto settings-hline: label flush left, control cluster flush right.
    private func labeled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 48, alignment: .leading)
            Spacer(minLength: 8)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func beginAdd() {
        draft = DraftConstant()
        selectedName = nil
        editing = true
        revealValue = true
        errorNote = nil
    }

    private func beginEdit(_ constant: SecretConstant) {
        draft = DraftConstant(from: constant)
        editing = true
        revealValue = false
        errorNote = nil
    }

    private func saveDraft() {
        errorNote = nil
        guard let name = SecretConstantsCatalog.normalizeName(draft.name) else {
            errorNote = "Name must be lowercase snake_case (e.g. phone_mobile)."
            return
        }
        let constant = SecretConstant(
            name: name,
            label: draft.label.trimmingCharacters(in: .whitespacesAndNewlines),
            hint: draft.hint,
            value: draft.value,
            allowedAgentIDs: Array(draft.allowedAgentIDs).sorted(),
            multiline: draft.multiline,
            updatedAt: Date()
        )
        do {
            try agents.upsertSecretConstant(constant)
            selectedName = name
            editing = false
            revealValue = false
        } catch {
            errorNote = String(describing: error)
        }
    }

    private func deleteSelected() {
        guard let name = selectedName ?? (draft.isExisting ? draft.name : nil) else { return }
        do {
            try agents.deleteSecretConstant(name: name)
            selectedName = catalog.constants.first?.name
            editing = false
        } catch {
            errorNote = String(describing: error)
        }
    }
}

private struct DraftConstant {
    var name: String = ""
    var label: String = ""
    var hint: SecretConstantHint = .other
    var value: String = ""
    var allowedAgentIDs: Set<String> = []
    var multiline: Bool = false
    var isExisting: Bool = false

    init() {}

    init(from constant: SecretConstant) {
        name = constant.name
        label = constant.label
        hint = constant.hint ?? .other
        value = constant.value
        allowedAgentIDs = Set(constant.allowedAgentIDs)
        multiline = constant.multiline
        isExisting = true
    }
}
