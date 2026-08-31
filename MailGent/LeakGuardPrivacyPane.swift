import MailStore
import SwiftUI

/// Grant Desk → Privacy: built-in detectors, custom rules, hit modes.
struct LeakGuardPrivacyPane: View {
    @Bindable var session: CompanionSession
    @Binding var expandedInfo: String?
    @State private var builtInsExpanded = true
    @State private var editingRule: CustomLeakRule?
    @State private var isAddingRule = false

    private var agents: AgentBridge { session.agents }
    private var isEditing: Bool { agents.isEditingGrants }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                LeakGuardMasterRow(
                    isOn: leakGuardBinding,
                    isEditing: isEditing,
                    peerTab: "Scope",
                    expandedInfo: $expandedInfo
                )
                GrantDeskInfoPanel(topic: .leakGuardMaster, expandedInfo: $expandedInfo)
                if agents.leakGuardEnabled, agents.leakGuardPolicy.scopes.isEmpty {
                    Text("No placements opted in — enable leak guard on Scope rows.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                GrantDeskCard(title: "Built-in detectors", topic: .privacyBuiltins, expandedInfo: $expandedInfo) {
                    GrantDeskInfoPanel(topic: .privacyBuiltins, expandedInfo: $expandedInfo)
                    DisclosureGroup("Show detectors", isExpanded: $builtInsExpanded) {
                        ForEach(BuiltInLeakClass.allCases, id: \.self) { leakClass in
                            builtInRow(leakClass)
                        }
                    }
                    .font(.callout)
                }
                .disabled(!isEditing || !agents.leakGuardEnabled)

                GrantDeskCard(title: "Custom filters", topic: .customFilters, expandedInfo: $expandedInfo) {
                    GrantDeskInfoPanel(topic: .customFilters, expandedInfo: $expandedInfo)
                    if agents.customLeakRules.isEmpty {
                        Text("No custom filters yet.")
                            .foregroundStyle(.secondary)
                            .font(.callout)
                    } else {
                        ForEach(agents.customLeakRules) { rule in
                            customRuleRow(rule)
                        }
                    }
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
                }
                .disabled(!agents.leakGuardEnabled)

                GrantDeskCard(title: "Hit modes", topic: .hitModes, expandedInfo: $expandedInfo) {
                    GrantDeskInfoPanel(topic: .hitModes, expandedInfo: $expandedInfo)
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
        }
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
    private func builtInRow(_ leakClass: BuiltInLeakClass) -> some View {
        HStack(spacing: 6) {
            Toggle(
                LeakGuardUI.builtInTitle(leakClass),
                isOn: builtInBinding(leakClass)
            )
            Spacer(minLength: 0)
            GrantDeskInfoButton(
                topic: .builtin(leakClass),
                expandedInfo: $expandedInfo,
                size: .small
            )
        }
        GrantDeskInfoPanel(topic: .builtin(leakClass), expandedInfo: $expandedInfo)
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

    static func builtInInfoBullets(_ leakClass: BuiltInLeakClass) -> [String] {
        switch leakClass {
        case .apiKeys:
            ["Examples: sk-live-abc123…, AKIAIOSFODNN7EXAMPLE, ghp_xxxxxxxx"]
        case .jwt:
            ["Examples: eyJhbGciOiJIUzI1NiIs…"]
        case .privateKeys:
            ["Examples: -----BEGIN RSA PRIVATE KEY-----"]
        case .passwordCtx:
            ["Examples: password=hunter2, secret: abc123"]
        case .creditCards:
            ["Examples: 4111 1111 1111 1111 — may match order numbers; pair with hit mode."]
        case .ssn:
            ["Examples: 123-45-6789"]
        case .phones:
            ["Examples: +1 555-0100 — custom literal rules better for known numbers."]
        case .emails:
            ["Examples: name@domain.tld — can be broad; disable if you only want custom address rules."]
        }
    }
}

// MARK: - Grant desk leak guard controls

extension AgentBridge {
    func leakGuardShieldState(accountID: String, placement: String?) -> LeakGuardShieldChip.State {
        let optedIn = isScopeInLeakGuardAllowlist(accountID: accountID, placement: placement)
        if !optedIn { return .off }
        return leakGuardEnabled ? .on : .pending
    }
}

struct GrantDeskInfoTopic: Equatable {
    let id: String
    let title: String
    let paragraphs: [String]
    let bullets: [String]

    static let leakGuardMaster = GrantDeskInfoTopic(
        id: "leak-guard-master",
        title: "Leak guard master switch",
        paragraphs: [
            "Global on/off for outbound sanitization. When off, MCP responses pass through after grant checks only — no heuristic scan, no custom rules."
        ],
        bullets: [
            "Runs on device after GrantGate, before JSON is returned to the agent.",
            "Scans subject + body only in v1 (headers like From/To are not scanned).",
            "Requires at least one placement with leak guard enabled; otherwise nothing is scanned even if master is on.",
            "Alpha policy: detector errors fail open (content passes unmodified)."
        ]
    )

    static let scopeOverview = GrantDeskInfoTopic(
        id: "scope-overview",
        title: "Scope tab",
        paragraphs: [
            "Scope decides which placements an agent may touch and sets default Access caps per row."
        ],
        bullets: [
            "Checkbox → allow or deny a mailbox (or whole account).",
            "Field badges (S/F/T/D/B/A/C) → per-placement grant caps; click to toggle what the agent may read.",
            "Leak guard L shield → opt-in scanning for that placement only. Grant must exist first."
        ]
    )

    static let grantFieldBadges = GrantDeskInfoTopic(
        id: "grant-field-badges",
        title: "Grant field badges",
        paragraphs: [
            "Compact caps for what the agent may read on this placement. Blue = granted; struck-through = withheld."
        ],
        bullets: [
            "S Subject · F From · T To · D Date",
            "B Body · A Attachment names · C Attachment content",
            "Denied fields return not_granted in MCP JSON and show red hatch in the access log."
        ]
    )

    static let shieldScan = GrantDeskInfoTopic(
        id: "shield-scan",
        title: "Leak guard icon (per placement)",
        paragraphs: [
            "Opt-in allowlist entry for leak guard. Same L shield icon everywhere — Scope rows, Access asset list, and docs."
        ],
        bullets: [
            "Click L on allowed rows to opt in; orange when active.",
            "Active → master on and placement opted in.",
            "Pending → opted in but master switch off.",
            "Off → not opted in.",
            "Account-wide grants show one icon for the whole account."
        ]
    )

    static let privacyBuiltins = GrantDeskInfoTopic(
        id: "privacy-builtins",
        title: "Built-in detectors",
        paragraphs: [
            "Heuristic regex classes applied to granted subject + body on opted-in placements. No Core ML in v1."
        ],
        bullets: [
            "Each class can be toggled independently.",
            "On match → redact with [REDACTED:category] unless a custom rule overlaps with replace action.",
            "Tap i on a detector row for examples, pattern detail, and false-positive notes."
        ]
    )

    static let customFilters = GrantDeskInfoTopic(
        id: "custom-filters",
        title: "Custom filters",
        paragraphs: [
            "User-defined patterns for names, addresses, internal IDs, etc."
        ],
        bullets: [
            "Literal — exact substring (optional case insensitive).",
            "Wildcard — * and ? glob, not path-style.",
            "Regex — invalid patterns blocked on save.",
            "Redact → marker in output; agent always sees sanitized.",
            "Replace → fake value; choose disclosed or stealth.",
            "Rules are global — they apply on every opted-in placement when enabled."
        ]
    )

    static let hitModes = GrantDeskInfoTopic(
        id: "hit-modes",
        title: "On confidential hit",
        paragraphs: [
            "Per-field behavior when any detector or custom rule matches."
        ],
        bullets: [
            "Redact / replace matching parts — only matched spans change; rest of field stays granted.",
            "Block entire field — whole subject or body withheld; MCP returns withheld_confidential.",
            "Subject and body can use different modes."
        ]
    )

    static func builtin(_ leakClass: BuiltInLeakClass) -> GrantDeskInfoTopic {
        GrantDeskInfoTopic(
            id: "builtin-\(leakClass.rawValue)",
            title: LeakGuardUI.builtInTitle(leakClass),
            paragraphs: [LeakGuardUI.builtInHelp(leakClass)],
            bullets: LeakGuardUI.builtInInfoBullets(leakClass)
        )
    }
}

struct GrantDeskInfoButton: View {
    let topic: GrantDeskInfoTopic
    @Binding var expandedInfo: String?
    var size: Size = .regular

    enum Size {
        case small
        case regular

        var dimension: CGFloat {
            switch self {
            case .small: 16
            case .regular: 18
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .small: 11
            case .regular: 12
            }
        }
    }

    private var isOn: Bool { expandedInfo == topic.id }

    var body: some View {
        Button {
            expandedInfo = isOn ? nil : topic.id
        } label: {
            Text("i")
                .font(.system(size: size.fontSize, weight: .semibold, design: .serif))
                .italic()
                .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                .frame(width: size.dimension, height: size.dimension)
                .background(
                    Circle().fill(
                        isOn ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.18)
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More information")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct GrantDeskInfoPanel: View {
    let topic: GrantDeskInfoTopic
    @Binding var expandedInfo: String?

    var body: some View {
        if expandedInfo == topic.id {
            VStack(alignment: .leading, spacing: 6) {
                Text(topic.title)
                    .font(.caption.weight(.semibold))
                ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !topic.bullets.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(topic.bullets.enumerated()), id: \.offset) { _, bullet in
                            Text("• \(bullet)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.97, green: 0.98, blue: 1.0), Color(red: 0.95, green: 0.97, blue: 0.99)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(red: 0.81, green: 0.88, blue: 0.96), lineWidth: 1)
            }
        }
    }
}

struct GrantDeskCard<Content: View>: View {
    let title: String
    var topic: GrantDeskInfoTopic? = nil
    @Binding var expandedInfo: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                if let topic {
                    GrantDeskInfoButton(topic: topic, expandedInfo: $expandedInfo, size: .small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
        }
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
        }
    }
}

struct LeakGuardMasterRow: View {
    @Binding var isOn: Bool
    let isEditing: Bool
    var peerTab: String = "Privacy"
    @Binding var expandedInfo: String?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Leak guard master")
                    .font(.callout.weight(.semibold))
                Text("Same switch as \(peerTab) — disables all scanning when off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            GrantDeskInfoButton(topic: .leakGuardMaster, expandedInfo: $expandedInfo)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(!isEditing)
                .accessibilityLabel("Leak guard master")
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.18), lineWidth: 0.5)
        }
    }
}

struct LeakGuardShieldChip: View {
    enum State {
        case off
        case pending
        case on
    }

    let state: State
    var interactive: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Group {
            if interactive, let action {
                Button(action: action) { chipLabel }
                    .buttonStyle(.plain)
            } else {
                chipLabel
            }
        }
        .help(helpText)
        .accessibilityLabel(accessibilityText)
    }

    private var chipLabel: some View {
        ZStack {
            Text("L")
                .font(.system(size: 8, weight: .semibold))
                .opacity(0)
            Image(systemName: "shield.fill")
                .font(.system(size: 9, weight: .medium))
            Text("L")
                .font(.system(size: 5.5, weight: .bold))
                .offset(y: 0.5)
        }
        .foregroundStyle(foreground)
        .frame(height: 14)
        .padding(.horizontal, 4)
        .background(Capsule().fill(background))
        .overlay {
            Capsule()
                .strokeBorder(border, lineWidth: 0.5)
        }
        .opacity(opacity)
    }

    private var foreground: Color {
        switch state {
        case .off: Color.secondary.opacity(0.55)
        case .pending: Color.orange.opacity(0.88)
        case .on: Color.orange
        }
    }

    private var background: Color {
        switch state {
        case .off: Color.secondary.opacity(0.08)
        case .pending: Color.orange.opacity(0.12)
        case .on: Color.orange.opacity(0.15)
        }
    }

    private var border: Color {
        switch state {
        case .off: Color.secondary.opacity(0.2)
        case .pending: Color.orange.opacity(0.25)
        case .on: Color.orange.opacity(0.35)
        }
    }

    private var opacity: Double {
        switch state {
        case .off: 0.38
        case .pending: 0.72
        case .on: 1
        }
    }

    private var helpText: String {
        switch state {
        case .off:
            "Leak guard — click to scan subject and body on MCP responses"
        case .pending:
            "Leak guard opted in — enable master switch to scan"
        case .on:
            "Leak guard — scanning subject and body on MCP responses"
        }
    }

    private var accessibilityText: String {
        switch state {
        case .off: "Leak guard off"
        case .pending: "Leak guard pending"
        case .on: "Leak guard on"
        }
    }
}

struct LeakGuardAccessRow: View {
    @Bindable var session: CompanionSession
    let grant: Grant
    let isEditing: Bool
    @Binding var expandedInfo: String?

    var body: some View {
        if session.agents.leakGuardEnabled {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Leak guard")
                            .font(.callout.weight(.medium))
                        Text("Scan subject & body before MCP responses leave MailGent")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    GrantDeskInfoButton(topic: .shieldScan, expandedInfo: $expandedInfo, size: .small)
                    Toggle(
                        "",
                        isOn: leakGuardScopeBinding
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!isEditing)
                    .accessibilityLabel("Leak guard scan")
                }
                GrantDeskInfoPanel(topic: .shieldScan, expandedInfo: $expandedInfo)
            }
            .padding(.vertical, 4)
        }
    }

    private var leakGuardScopeBinding: Binding<Bool> {
        Binding(
            get: {
                session.agents.isScopeInLeakGuardAllowlist(
                    accountID: grant.accountID,
                    placement: grant.placement
                )
            },
            set: { newValue in
                let current = session.agents.isScopeInLeakGuardAllowlist(
                    accountID: grant.accountID,
                    placement: grant.placement
                )
                if newValue != current {
                    session.agents.toggleLeakGuardScope(
                        accountID: grant.accountID,
                        placement: grant.placement
                    )
                }
            }
        )
    }
}

struct LeakGuardScopeControls: View {
    @Bindable var session: CompanionSession
    let accountID: String
    let placement: String?
    let isEditing: Bool
    @Binding var expandedInfo: String?

    var body: some View {
        let agents = session.agents
        let state = agents.leakGuardShieldState(accountID: accountID, placement: placement)
        HStack(spacing: 4) {
            GrantDeskInfoButton(topic: .shieldScan, expandedInfo: $expandedInfo, size: .small)
            LeakGuardShieldChip(
                state: state,
                interactive: isEditing,
                action: {
                    agents.toggleLeakGuardScope(accountID: accountID, placement: placement)
                }
            )
        }
    }
}
