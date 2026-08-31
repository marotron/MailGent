import MailStore
import SwiftUI

/// Grant Desk → Privacy: built-in detectors, custom rules, hit modes.
struct LeakGuardPrivacyPane: View {
    @Bindable var session: CompanionSession
    @State private var builtInsExpanded = false
    @State private var editingRule: CustomLeakRule?
    @State private var isAddingRule = false

    private var agents: AgentBridge { session.agents }
    private var isEditing: Bool { agents.isEditingGrants }

    var body: some View {
        Form {
            Section {
                Toggle("Leak guard", isOn: leakGuardBinding)
                    .disabled(!isEditing)
                Text(
                    "On-device scan of subject and body before agents receive mail. Opt in placements on Scope."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                if agents.leakGuardEnabled, agents.leakGuardPolicy.scopes.isEmpty {
                    Text("No placements opted in — enable Scan on Scope rows.")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                DisclosureGroup("Built-in detectors", isExpanded: $builtInsExpanded) {
                    ForEach(BuiltInLeakClass.allCases, id: \.self) { leakClass in
                        Toggle(
                            LeakGuardUI.builtInTitle(leakClass),
                            isOn: builtInBinding(leakClass)
                        )
                        .help(LeakGuardUI.builtInHelp(leakClass))
                    }
                }
            }
            .disabled(!isEditing || !agents.leakGuardEnabled)

            Section("Custom filters") {
                if agents.customLeakRules.isEmpty {
                    Text("No custom filters yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    ForEach(agents.customLeakRules) { rule in
                        customRuleRow(rule)
                    }
                    .onMove(perform: moveRules)
                    .onDelete(perform: deleteRules)
                }
                HStack {
                    Button("Add filter…") {
                        editingRule = CustomLeakRule(
                            label: "Custom filter",
                            kind: .literal,
                            pattern: "",
                            action: .redact,
                            actionValue: ""
                        )
                        isAddingRule = true
                    }
                    .disabled(!isEditing || !agents.leakGuardEnabled)
                    Spacer()
                }
            }
            .disabled(!agents.leakGuardEnabled)

            Section("Hit modes") {
                Picker("Subject", selection: subjectHitModeBinding) {
                    Text("Redact matching spans").tag(LeakGuardHitMode.redactSpans)
                    Text("Block whole field").tag(LeakGuardHitMode.blockWhole)
                }
                Picker("Body", selection: bodyHitModeBinding) {
                    Text("Redact matching spans").tag(LeakGuardHitMode.redactSpans)
                    Text("Block whole field").tag(LeakGuardHitMode.blockWhole)
                }
            }
            .disabled(!isEditing || !agents.leakGuardEnabled)
        }
        .formStyle(.grouped)
        .id(agents.leakGuardRevision)
        .sheet(item: $editingRule) { draft in
            CustomLeakRuleEditor(
                rule: draft,
                isNew: isAddingRule,
                onSave: { saved in
                    if isAddingRule {
                        agents.addCustomLeakRule(saved)
                    } else {
                        agents.updateCustomLeakRule(saved)
                    }
                    editingRule = nil
                    isAddingRule = false
                },
                onCancel: {
                    editingRule = nil
                    isAddingRule = false
                }
            )
        }
    }

    private var leakGuardBinding: Binding<Bool> {
        Binding(
            get: { agents.leakGuardEnabled },
            set: { agents.setLeakGuardEnabled($0) }
        )
    }

    private func builtInBinding(_ leakClass: BuiltInLeakClass) -> Binding<Bool> {
        Binding(
            get: { agents.leakGuardPolicy.builtInClasses[leakClass] ?? false },
            set: { agents.setBuiltInLeakClass(leakClass, enabled: $0) }
        )
    }

    private var subjectHitModeBinding: Binding<LeakGuardHitMode> {
        Binding(
            get: { agents.leakGuardPolicy.subjectHitMode },
            set: { agents.setSubjectHitMode($0) }
        )
    }

    private var bodyHitModeBinding: Binding<LeakGuardHitMode> {
        Binding(
            get: { agents.leakGuardPolicy.bodyHitMode },
            set: { agents.setBodyHitMode($0) }
        )
    }

    @ViewBuilder
    private func customRuleRow(_ rule: CustomLeakRule) -> some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.label)
                    .font(.callout.weight(.medium))
                Text(rule.pattern)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !rule.enabled {
                Text("off")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Button("Edit") {
                editingRule = rule
                isAddingRule = false
            }
            .buttonStyle(.borderless)
            .disabled(!isEditing)
        }
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        guard isEditing else { return }
        agents.moveCustomLeakRules(from: source, to: destination)
    }

    private func deleteRules(at offsets: IndexSet) {
        guard isEditing else { return }
        for index in offsets {
            let id = agents.customLeakRules[index].id
            agents.removeCustomLeakRule(id: id)
        }
    }
}

// MARK: - Custom rule editor

private struct CustomLeakRuleEditor: View {
    @State private var rule: CustomLeakRule
    let isNew: Bool
    let onSave: (CustomLeakRule) -> Void
    let onCancel: () -> Void

    @State private var validationError: String?

    init(
        rule: CustomLeakRule,
        isNew: Bool,
        onSave: @escaping (CustomLeakRule) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _rule = State(initialValue: rule)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(isNew ? "Add custom filter" : "Edit custom filter")
                .font(.headline)
                .padding()
            Form {
                TextField("Label", text: $rule.label)
                Picker("Match kind", selection: $rule.kind) {
                    Text("Literal").tag(CustomLeakRule.Kind.literal)
                    Text("Wildcard").tag(CustomLeakRule.Kind.wildcard)
                    Text("Regular expression").tag(CustomLeakRule.Kind.regex)
                }
                TextField("Pattern", text: $rule.pattern)
                Toggle("Case insensitive", isOn: $rule.caseInsensitive)
                Picker("Action", selection: $rule.action) {
                    Text("Redact").tag(CustomLeakRule.Action.redact)
                    Text("Replace").tag(CustomLeakRule.Action.replace)
                }
                if rule.action == .replace {
                    TextField("Replacement value", text: $rule.actionValue)
                    Toggle("Disclose sanitization to agent", isOn: $rule.discloseToAgent)
                        .help("Off = stealth replace; agent sees granted text.")
                }
                Toggle("Enabled", isOn: $rule.enabled)
                if let validationError {
                    Text(validationError)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                Button(isNew ? "Add" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 420)
    }

    private func save() {
        let trimmedLabel = rule.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedLabel.isEmpty else {
            validationError = "Label cannot be empty."
            return
        }
        if let patternError = CustomLeakRule.validatePattern(kind: rule.kind, pattern: rule.pattern) {
            validationError = patternError
            return
        }
        rule.label = trimmedLabel
        validationError = nil
        onSave(rule)
    }
}

// MARK: - Display helpers

enum LeakGuardUI {
    static func builtInTitle(_ leakClass: BuiltInLeakClass) -> String {
        switch leakClass {
        case .apiKeys: "API keys"
        case .jwt: "JWT tokens"
        case .privateKeys: "Private keys"
        case .passwordCtx: "Password patterns"
        case .creditCards: "Credit cards"
        case .ssn: "SSN"
        case .phones: "Phone numbers"
        case .emails: "Email addresses"
        }
    }

    static func builtInHelp(_ leakClass: BuiltInLeakClass) -> String {
        switch leakClass {
        case .apiKeys:
            "sk-…, AKIA…, ghp_… style secrets"
        case .jwt:
            "eyJ… three-part JWT tokens"
        case .privateKeys:
            "PEM blocks (BEGIN … PRIVATE KEY)"
        case .passwordCtx:
            "password:/secret:/token: assignments"
        case .creditCards:
            "13–19 digit card number runs"
        case .ssn:
            "NNN-NN-NNNN"
        case .phones:
            "Phone-like digit runs"
        case .emails:
            "Email address patterns"
        }
    }
}

struct LeakGuardScanToggle: View {
    @Bindable var session: CompanionSession
    let accountID: String
    let placement: String?
    let isEditing: Bool

    var body: some View {
        let agents = session.agents
        let on = agents.isScopeInLeakGuardAllowlist(accountID: accountID, placement: placement)
        Toggle("Scan", isOn: Binding(
            get: { on },
            set: { _ in agents.toggleLeakGuardScope(accountID: accountID, placement: placement) }
        ))
        .toggleStyle(.switch)
        .controlSize(.small)
        .labelsHidden()
        .help("Scan subject and body for this placement when leak guard is on")
        .disabled(!isEditing || !agents.leakGuardEnabled)
        .accessibilityLabel(on ? "Scan on" : "Scan off")
    }
}
