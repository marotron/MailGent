import MailStore
import SwiftUI

/// Lean grant desk: agent Scope/Access, mailbox-wide Rules/Privacy via Shared pick.
struct GrantDeskView: View {
    @Bindable var session: CompanionSession
    @AppStorage(MailGentPreferences.allowConditionalAccessPromptsKey)
    private var allowConditionalAccessPrompts = false
    @State private var tab: Tab = .scope
    @State private var deskFocus: DeskFocus = .agent
    @State private var expandedInfo: String?
    @State private var selectedPassID: String?

    /// Top picker: a paired agent (Scope/Access) or Shared (Rules/Privacy).
    private enum DeskFocus: Equatable {
        case agent
        case shared
    }

    enum Tab: String, Identifiable {
        case scope = "Scope"
        case access = "Access"
        case rules = "Rules"
        case privacy = "Privacy"
        var id: String { rawValue }

        static let agentTabs: [Tab] = [.scope, .access]
        static let sharedTabs: [Tab] = [.rules, .privacy]

        var isAgentTab: Bool {
            Self.agentTabs.contains(self)
        }
    }

    private var isEditing: Bool { session.agents.isEditingGrants }
    private var visibleTabs: [Tab] {
        deskFocus == .shared ? Tab.sharedTabs : Tab.agentTabs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            agentPickerRow

            if session.agents.pairedAgents.isEmpty {
                ContentUnavailableView(
                    "No agent paired",
                    systemImage: "cpu",
                    description: Text("Pair Cursor or Grok Bot in the companion, then edit grants here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Picker("", selection: $tab) {
                        ForEach(visibleTabs) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 220)
                    .accessibilityLabel("Grant desk section")

                    Spacer(minLength: 8)
                    editModeControls
                }

                switch tab {
                case .scope:
                    scopePane
                case .rules:
                    PassDeskPane(
                        session: session,
                        selectedPassID: $selectedPassID,
                        isEditing: isEditing
                    )
                case .access:
                    accessPane
                case .privacy:
                    LeakGuardPrivacyPane(session: session, expandedInfo: $expandedInfo)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 560)
    }

    private var agentPickerRow: some View {
        HStack(spacing: 8) {
            Text("Agent")
                .font(.caption)
                .foregroundStyle(.secondary)
            if session.agents.pairedAgents.isEmpty {
                Text("—")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                agentSharedPick
                    .disabled(isEditing)
                    .help(
                        isEditing
                            ? "Save or cancel edits before switching"
                            : "Agent: Scope & Access · Shared: Rules & Privacy"
                    )
            }
            Spacer(minLength: 0)
            if deskFocus == .shared {
                Text("Mailbox-wide · rules + privacy")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let agent = session.agents.selectedAgent {
                Text("\(agent.name) · \(agent.trustClass.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var agentSharedPick: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                ForEach(session.agents.pairedAgents) { agent in
                    let selected = deskFocus == .agent
                        && (session.agents.selectedAgentID ?? session.agents.pairedAgents.first?.id)
                        == agent.id
                    GrantDeskPickButton(
                        title: agent.name,
                        selected: selected
                    ) {
                        AgentGlyph(name: agent.name, size: 14)
                    } action: {
                        selectDeskAgent(id: agent.id)
                    }
                }
            }
            .padding(2)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 22)

            HStack(spacing: 2) {
                GrantDeskPickButton(
                    title: "Shared",
                    selected: deskFocus == .shared
                ) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(deskFocus == .shared ? Color.primary : Color.secondary)
                        .frame(width: 14, height: 14)
                        .background(
                            Color(nsColor: .quaternaryLabelColor).opacity(0.22),
                            in: Circle()
                        )
                } action: {
                    selectDeskShared()
                }
            }
            .padding(2)
            .background(Color(nsColor: .quaternaryLabelColor).opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Agent or shared settings")
    }

    private func selectDeskAgent(id: String) {
        if deskFocus != .agent || session.agents.selectedAgentID != id {
            if isEditing { return }
            deskFocus = .agent
            session.agents.selectAgent(id: id)
            if !tab.isAgentTab {
                tab = .scope
            }
        }
    }

    private func selectDeskShared() {
        guard deskFocus != .shared else { return }
        if isEditing { return }
        deskFocus = .shared
        if tab.isAgentTab {
            tab = .rules
        }
    }

    @ViewBuilder
    private var editModeControls: some View {
        if isEditing {
            HStack(spacing: 6) {
                Button("Cancel") {
                    session.agents.cancelGrantDeskEdits()
                }
                Button("Save") {
                    session.agents.commitGrantDeskEdits()
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        } else {
            Button("Edit") {
                session.agents.beginGrantDeskEdits()
            }
            .controlSize(.small)
            .help("Unlock to change grants")
            .accessibilityLabel("Edit grants")
        }
    }

    private var scopePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            LeakGuardMasterRow(
                isOn: Binding(
                    get: { session.agents.leakGuardEnabled },
                    set: { session.agents.setLeakGuardEnabled($0) }
                ),
                isEditing: isEditing,
                peerTab: "Shared · Privacy",
                expandedInfo: $expandedInfo
            )
            GrantDeskInfoPanel(topic: .leakGuardMaster, expandedInfo: $expandedInfo)
            if session.agents.leakGuardEnabled, session.agents.leakGuardPolicy.scopes.isEmpty {
                Text("Leak guard is on but no placements are opted in for scanning.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            GrantDeskCard(title: "Allowed placements", topic: .scopeOverview, expandedInfo: $expandedInfo) {
                GrantDeskInfoPanel(topic: .scopeOverview, expandedInfo: $expandedInfo)
                scopeHintRow
                if session.scanCatalog.isEmpty {
                    Text("Index accounts first.")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(session.scanCatalog) { account in
                                accountBlock(account)
                            }
                        }
                        .padding(.vertical, 2)
                        .id(session.agents.grantRevision)
                        .id(session.agents.leakGuardRevision)
                        .id(session.agents.ruleRevision)
                    }
                    .frame(maxHeight: 340)
                }
            }

            if isEditing, !session.agents.grantRows.isEmpty {
                Button("Clear all grants", role: .destructive) {
                    session.agents.clearGrants()
                }
            }

            if !session.agents.allowGrants.isEmpty {
                Text("Detectors & custom rules → Shared · Privacy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accessPane: some View {
        let allows = session.agents.allowGrants
        return Group {
            if allows.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No placement assets yet. Allow mailboxes on Scope first.")
                        .foregroundStyle(.secondary)
                    Button("← Scope") { tab = .scope }
                }
            } else {
                let selected = session.agents.selectedAccessGrant() ?? allows[0]
                HStack(alignment: .top, spacing: 12) {
                    assetList(allows: allows, selected: selected)
                        .frame(width: 280, alignment: .top)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            fieldEditor(for: selected)
                            Divider()
                            Text("Preview")
                                .font(.subheadline.weight(.semibold))
                            previewCaption(for: selected)
                            AgentAccessPreview(session: session, grant: selected)
                                .id("\(session.agents.grantRevision)-\(session.agents.ruleRevision)-\(session.agents.leakGuardRevision)-\(AgentBridge.accessKey(for: selected))")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        }
    }

    private func assetList(allows: [Grant], selected: Grant) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Assets")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(allows.enumerated()), id: \.offset) { _, grant in
                        let on = AgentBridge.accessKey(for: grant)
                            == AgentBridge.accessKey(for: selected)
                        Button {
                            session.agents.selectAccessGrant(grant)
                        } label: {
                            accessAssetLabel(grant)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(on ? Color.accentColor.opacity(0.12) : Color.clear)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var scopeHintRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Check placements to allow. Field badges = Access caps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GrantDeskInfoButton(topic: .grantFieldBadges, expandedInfo: $expandedInfo, size: .small)
                Text(
                    allowConditionalAccessPrompts
                        ? "· Click chips: Off → Ask → On · Leak guard"
                        : "· Click chips: Off ↔ On (Ask paused) · Leak guard"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GrantDeskInfoButton(topic: .shieldScan, expandedInfo: $expandedInfo, size: .small)
                Text("= opt-in scanning.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            GrantDeskInfoPanel(topic: .grantFieldBadges, expandedInfo: $expandedInfo)
            GrantDeskInfoPanel(topic: .shieldScan, expandedInfo: $expandedInfo)
        }
    }

    private func previewCaption(for grant: Grant) -> some View {
        let scanning = session.agents.leakGuardEnabled
            && session.agents.isScopeInLeakGuardAllowlist(
                accountID: grant.accountID,
                placement: grant.placement
            )
        let suffix = scanning ? " · leak guard active" : ""
        return Text("Sample message under this placement’s caps\(suffix).")
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    private func fieldEditor(for grant: Grant) -> some View {
        let fields = grant.fields
        return VStack(alignment: .leading, spacing: 6) {
            Text(pathLabel(grant))
                .font(.headline)
            Text("Fields are the Scope base. Matching Pass/Block rules overwrite fields on allowed mail.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(
                allowConditionalAccessPrompts
                    ? "Click a field chip to cycle Off → Ask → On. Ask prompts once per MCP get."
                    : "Allow conditional access is off — Ask fields show and act as Off. Turn it on in Settings to restore Ask."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            LeakGuardAccessRow(
                session: session,
                grant: grant,
                isEditing: isEditing,
                expandedInfo: $expandedInfo
            )

            HStack(alignment: .center, spacing: 8) {
                Text("Presets")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    presetButton("Headers only", GrantFields.headersOnly, grant)
                    presetButton("Read mail", GrantFields(
                        subject: true, from: true, to: true, date: true,
                        body: true, attachmentMetadata: false, attachmentContent: false
                    ), grant)
                    presetButton("Full", GrantFields(
                        subject: true, from: true, to: true, date: true,
                        body: true, attachmentMetadata: true, attachmentContent: true
                    ), grant)
                }
            }
            .padding(.top, 4)
            .disabled(!isEditing)

            Text("Envelope")
                .font(.caption.weight(.semibold))
                .padding(.top, 4)
            GrantChipFlow(spacing: 6) {
                fieldBadge("Subject", grant, \.subjectMode, systemImage: "text.alignleft")
                fieldBadge("From", grant, \.fromMode, systemImage: "envelope")
                fieldBadge("To", grant, \.toMode, systemImage: "envelope")
                fieldBadge("Cc", grant, \.ccMode, systemImage: "person.2")
                fieldBadge("Date & Time", grant, \.dateMode, systemImage: "calendar")
            }
            .disabled(!isEditing)
            Text("Content")
                .font(.caption.weight(.semibold))
                .padding(.top, 4)
            GrantChipFlow(spacing: 6) {
                fieldBadge(
                    "Body / snippet",
                    grant,
                    \.bodyMode,
                    systemImage: "text.alignleft"
                )
                fieldBadge(
                    "Attachment names",
                    grant,
                    \.attachmentMetadataMode,
                    systemImage: "paperclip"
                )
                fieldBadge(
                    "Attachment content",
                    grant,
                    \.attachmentContentMode,
                    systemImage: "paperclip"
                )
            }
            .disabled(!isEditing)

            VStack(alignment: .leading, spacing: 4) {
                Text("Rules on this placement")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if session.agents.ruleDefinitions.isEmpty {
                    Text("No rules yet — create one on the Rules tab.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    PassToggleChips(
                        session: session,
                        accountID: grant.accountID,
                        placement: grant.placement,
                        isEditing: isEditing,
                        density: .roomy
                    )
                }
            }
            .padding(.top, 6)
        }
    }

    private func presetButton(_ title: String, _ fields: GrantFields, _ grant: Grant) -> some View {
        let on = grant.fields == fields
        return Button(title) {
            session.agents.updateAllowFields(
                accountID: grant.accountID,
                placement: grant.placement,
                fields: fields
            )
        }
        .buttonStyle(.bordered)
        .tint(on ? .accentColor : nil)
        .controlSize(.small)
    }

    private func fieldBadge(
        _ title: String,
        _ grant: Grant,
        _ modeKeyPath: WritableKeyPath<GrantFields, FieldAccessMode>,
        systemImage: String? = nil
    ) -> some View {
        let stored = grant.fields[keyPath: modeKeyPath]
        let mode = stored.displayed(allowConditional: allowConditionalAccessPrompts)
        return Button {
            session.agents.cycleFieldAccessMode(
                accountID: grant.accountID,
                placement: grant.placement,
                modeKeyPath: modeKeyPath
            )
        } label: {
            GrantFieldChip(
                title: title,
                isOn: mode == .on,
                systemImage: systemImage,
                mode: mode
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEditing)
        .help(fieldModeHelp(stored: stored, displayed: mode, title: title))
    }
    
    private func fieldModeHelp(
        stored: FieldAccessMode,
        displayed: FieldAccessMode,
        title: String
    ) -> String {
        if !allowConditionalAccessPrompts && stored == .ask {
            return "\(title): Ask paused (shows Off) — enable Allow conditional access prompts in Settings to restore"
        }
        switch displayed {
        case .off: return "\(title): Off — agent cannot access"
        case .on: return "\(title): On — agent may access freely"
        case .ask: return "\(title): Ask — prompt before each access"
        }
    }

    private func displayedFields(_ fields: GrantFields) -> GrantFields {
        fields.displayed(allowConditional: allowConditionalAccessPrompts)
    }

    private func accountBlock(_ account: DetectedAccount) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                GrantCheckRow(
                    title: account.displayName ?? CompanionAccounts.label(account.id),
                    isOn: session.agents.hasAccountWideGrant(accountID: account.id),
                    emphasized: true
                ) {
                    session.agents.setAccountWide(
                        accountID: account.id,
                        enabled: !session.agents.hasAccountWideGrant(accountID: account.id)
                    )
                }
                .disabled(!isEditing)
                if let grant = session.agents.allowGrant(accountID: account.id, placement: nil),
                   session.agents.hasAccountWideGrant(accountID: account.id) {
                    scopeBadgeRow(
                        fields: displayedFields(grant.fields),
                        accountID: account.id,
                        placement: nil,
                        showsLeakGuard: true,
                        interactive: isEditing
                    ) { keyPath in
                        session.agents.cycleAllowField(
                            accountID: account.id,
                            placement: nil,
                            keyPath: keyPath
                        )
                    }
                    PassToggleChips(
                        session: session,
                        accountID: account.id,
                        placement: nil,
                        isEditing: isEditing
                    )
                }
            }

            ForEach(account.mailboxes) { mailbox in
                let denied = session.agents.hasMailboxDeny(
                    accountID: account.id,
                    placement: mailbox.placement
                )
                let accountWide = session.agents.hasAccountWideGrant(accountID: account.id)
                let mbGrant = session.agents.allowGrant(
                    accountID: account.id,
                    placement: mailbox.placement
                )
                let allowed = accountWide || mbGrant != nil
                HStack(alignment: .top, spacing: 8) {
                    GrantCheckRow(
                        title: mailbox.placement,
                        isOn: allowed,
                        badge: denied ? "deny" : nil
                    ) {
                        session.agents.setMailbox(
                            accountID: account.id,
                            placement: mailbox.placement,
                            enabled: !allowed
                        )
                    }
                    .disabled(!isEditing || accountWide)
                    if allowed,
                       let fields = session.agents.effectiveAllowFields(
                           accountID: account.id,
                           placement: mailbox.placement
                       ) {
                        scopeBadgeRow(
                            fields: displayedFields(fields),
                            accountID: account.id,
                            placement: mailbox.placement,
                            showsLeakGuard: !accountWide,
                            interactive: isEditing
                        ) { keyPath in
                            session.agents.cycleAllowField(
                                accountID: account.id,
                                placement: mailbox.placement,
                                keyPath: keyPath,
                                mailboxPlacements: account.mailboxes.map(\.placement)
                            )
                        }
                        PassToggleChips(
                            session: session,
                            accountID: account.id,
                            placement: mailbox.placement,
                            isEditing: isEditing
                        )
                    }
                }
                .padding(.leading, 16)
            }
        }
    }

    private func accessAssetLabel(_ grant: Grant) -> some View {
        let shieldState = session.agents.leakGuardShieldState(
            accountID: grant.accountID,
            placement: grant.placement
        )
        let rules = session.agents.enabledRules(
            accountID: grant.accountID,
            placement: grant.placement
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(pathLabel(grant))
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                GrantFieldBadgeRow(
                    fields: displayedFields(grant.fields),
                    interactive: false
                )
                if shieldState != .off {
                    LeakGuardShieldChip(state: shieldState)
                }
                AccessTabRuleCountBadges(rules: rules)
            }
        }
    }

    private func pathLabel(_ grant: Grant) -> String {
        let account = session.scanCatalog.first { $0.id == grant.accountID }
        let name = account?.displayName
            ?? CompanionAccounts.label(grant.accountID)
        if let placement = grant.placement {
            return "\(name) / \(placement)"
        }
        return "\(name) · all mailboxes"
    }

    @ViewBuilder
    private func scopeBadgeRow(
        fields: GrantFields,
        accountID: String,
        placement: String?,
        showsLeakGuard: Bool,
        interactive: Bool,
        onToggle: @escaping (WritableKeyPath<GrantFields, Bool>) -> Void
    ) -> some View {
        HStack(spacing: 4) {
            if showsLeakGuard {
                LeakGuardScopeControls(
                    session: session,
                    accountID: accountID,
                    placement: placement,
                    isEditing: interactive,
                    expandedInfo: $expandedInfo
                )
            }
            GrantFieldBadgeRow(fields: fields, interactive: interactive, onToggle: onToggle)
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Agent / Shared pick chrome

private struct GrantDeskPickButton<Icon: View>: View {
    let title: String
    let selected: Bool
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon()
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)
            .padding(.vertical, 4)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 0.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Access sample preview (hatch + rule effects)

/// Compact Access-tab list marks: green ✓ + pass count, red ✗ + block count (no nick letters).
private struct AccessTabRuleCountBadges: View {
    let rules: [GrantRule]

    private var passCount: Int { rules.filter { $0.polarity == .pass }.count }
    private var blockCount: Int { rules.filter { $0.polarity == .block }.count }

    var body: some View {
        HStack(spacing: 4) {
            if passCount > 0 {
                AccessTabRuleCountBadge(polarity: .pass, count: passCount)
            }
            if blockCount > 0 {
                AccessTabRuleCountBadge(polarity: .block, count: blockCount)
            }
        }
    }
}

private struct AccessTabRuleCountBadge: View {
    let polarity: RulePolarity
    let count: Int

    private var color: Color {
        polarity == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed
    }

    private var accessibilityText: String {
        switch polarity {
        case .pass:
            return count == 1 ? "1 Pass enabled" : "\(count) Passes enabled"
        case .block:
            return count == 1 ? "1 Block enabled" : "\(count) Blocks enabled"
        }
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: polarity == .pass ? "checkmark" : "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 14, height: 14)
                .background(Circle().fill(color.opacity(0.12)))
                .overlay {
                    Circle().strokeBorder(color.opacity(0.45), lineWidth: 0.5)
                }

            Text("\(count)")
                .font(.caption2.weight(.semibold).monospacedDigit())
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .help(accessibilityText)
        .layoutPriority(1)
    }
}

private struct AgentAccessPreview: View {
    let session: CompanionSession
    let grant: Grant

    private var attached: [GrantRule] {
        session.agents.enabledRules(accountID: grant.accountID, placement: grant.placement)
    }

    private var sample: SampleMessage {
        SampleMessage.forAccessPreview(matching: attached.first)
    }

    private var indexedSample: IndexedMessage {
        IndexedMessage(
            id: "sample",
            accountID: grant.accountID,
            placement: grant.placement ?? "INBOX",
            from: sample.from,
            to: sample.to,
            cc: sample.cc,
            date: sample.date,
            subject: sample.subject,
            body: sample.body,
            isPartial: false
        )
    }

    private var effectiveFields: GrantFields {
        guard let agentID = session.agents.selectedAgent?.id else { return grant.fields }
        return RuleEngine.applyOverlays(
            base: grant.fields,
            message: indexedSample,
            agentID: agentID,
            rules: session.agents.ruleDefinitions,
            enablements: session.agents.rules.allEnablements()
        )
    }

    private var firedRules: [GrantRule] {
        guard let agentID = session.agents.selectedAgent?.id else { return [] }
        let enablements = session.agents.rules.allEnablements()
        return attached.filter {
            RuleEngine.matches($0, message: indexedSample, agentID: agentID, enablements: enablements)
        }
    }

    private func viaPassNick(for keyPath: KeyPath<GrantFields, Bool>) -> String? {
        guard !grant.fields[keyPath: keyPath], effectiveFields[keyPath: keyPath],
              let pass = firedRules.first(where: {
                  $0.polarity == .pass && $0.fields[keyPath: keyPath]
              })
        else { return nil }
        return pass.nick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !sampleRef.displayLeakDetections.isEmpty {
                LeakGuardDetectionsList(detections: sampleRef.displayLeakDetections)
            }
            MessageAccessCard(
                session: session,
                ref: sampleRef,
                showsFieldBadges: false,
                attachmentContentDetail: sample.attachmentContentDetail,
                bodyViaPassNick: viaPassNick(for: \.body),
                attachmentInfoViaPassNick: viaPassNick(for: \.attachmentMetadata),
                attachmentContentViaPassNick: viaPassNick(for: \.attachmentContent)
            )
            ForEach(firedRules) { pass in
                Text(ruleNote(pass))
                    .font(.system(size: 10))
                    .foregroundStyle(
                        pass.polarity == .pass ? RuleMarkStyle.passGreen : RuleMarkStyle.blockRed
                    )
            }
            if !attached.isEmpty, firedRules.isEmpty {
                Text("Attached rules did not match this sample (or their fields are already covered).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if AccessLogFormat.showsSanitizedLegend(for: [sampleRef]) {
                SanitizedFieldsLegend()
            }
            if hasLockedFields {
                LockedFieldsLegend()
            }
        }
        .id("\(session.agents.leakGuardRevision)-\(session.agents.ruleRevision)")
    }

    private var hasLockedFields: Bool {
        let f = effectiveFields
        return !f.subject || !f.from || !f.to || !f.cc || !f.date
            || !f.body || !f.attachmentMetadata || !f.attachmentContent
    }

    private func ruleNote(_ rule: GrantRule) -> String {
        if rule.polarity == .block {
            let labels = fieldLabels(on: rule.fields)
            let joined = labels.isEmpty ? "fields" : labels.joined(separator: ", ")
            return "BLOCK — \(rule.name) (✗ \(rule.nick)) withheld \(joined)."
        }
        let labels = greenLitLabels(rule: rule, base: grant.fields)
        let joined = labels.isEmpty ? "fields" : labels.joined(separator: ", ")
        return "PASS — \(rule.name) (✓ \(rule.nick)) green-lit \(joined)."
    }

    private func fieldLabels(on fields: GrantFields) -> [String] {
        var labels: [String] = []
        if fields.body { labels.append("body") }
        if fields.attachmentMetadata { labels.append("attachment names") }
        if fields.attachmentContent { labels.append("attachment content") }
        if fields.subject { labels.append("subject") }
        if fields.from { labels.append("from") }
        if fields.to { labels.append("to") }
        if fields.cc { labels.append("cc") }
        if fields.date { labels.append("date") }
        return labels
    }

    private func greenLitLabels(rule: GrantRule, base: GrantFields) -> [String] {
        var labels: [String] = []
        if rule.fields.body && !base.body { labels.append("body") }
        if rule.fields.attachmentMetadata && !base.attachmentMetadata { labels.append("attachment names") }
        if rule.fields.attachmentContent && !base.attachmentContent { labels.append("attachment content") }
        if rule.fields.subject && !base.subject { labels.append("subject") }
        if rule.fields.from && !base.from { labels.append("from") }
        if rule.fields.to && !base.to { labels.append("to") }
        if rule.fields.cc && !base.cc { labels.append("cc") }
        if rule.fields.date && !base.date { labels.append("date") }
        return labels
    }

    private var sampleRef: AuditMessageRef {
        let fields = effectiveFields
        let scanPlacement = grant.placement ?? "INBOX"
        let leakGuard = OutboundLeakGuard(policy: session.agents.leakGuardPolicy)
        let subjectField = leakGuard.sanitize(
            text: sample.subject,
            field: .subject,
            accountID: grant.accountID,
            placement: scanPlacement,
            fieldGranted: fields.subject
        )
        let bodyField = leakGuard.sanitize(
            text: sample.body,
            field: .body,
            accountID: grant.accountID,
            placement: scanPlacement,
            fieldGranted: fields.body
        )
        let disclosed = Array(Set(subjectField.disclosedRules + bodyField.disclosedRules)).sorted()
        return AuditMessageRef(
            accountID: grant.accountID,
            placement: grant.placement ?? "all mailboxes",
            id: "sample",
            subject: displayText(subjectField, granted: fields.subject),
            from: sample.from,
            date: sample.date,
            to: sample.to,
            cc: sample.cc,
            bodySnippet: displayText(bodyField, granted: fields.body),
            subjectAccess: fields.subject ? subjectField.access.auditBodyAccess : .notGranted,
            bodyAccess: fields.body ? bodyField.access.auditBodyAccess : .notGranted,
            subjectOriginal: subjectField.original != subjectField.text ? subjectField.original : nil,
            bodyOriginal: bodyField.original != bodyField.text ? bodyField.original : nil,
            sanitizedRules: disclosed.isEmpty ? nil : disclosed,
            stealth: subjectField.stealth || bodyField.stealth,
            leakDetections: AuditLeakDetection.from(subject: subjectField, body: bodyField),
            fields: fields,
            attachments: fields.attachmentMetadata ? sample.mailAttachments : []
        )
    }

    private func displayText(_ field: SanitizedField, granted: Bool) -> String {
        guard granted else { return "" }
        if field.access == .withheldConfidential { return "" }
        return field.text
    }
}

private struct SampleMessage {
    let subject: String
    let from: String
    let to: String
    let cc: String
    let date: String
    let body: String
    let attachments: [(name: String, kb: Int)]

    static let invoice = SampleMessage(
        subject: "Invoice #4412 — March hosting",
        from: "billing@hostco.example",
        to: "you@yahoo.com",
        cc: "finance@hostco.example",
        date: "2026-03-12T09:14:00Z",
        body: "Hi,\n\nAttached is your March invoice ($48.00).\nAPI key: sk-live-demo1234567890\nCard ending 4412 was charged.\n\nThanks,\nHostCo billing",
        attachments: [
            ("invoice-4412.pdf", 82),
            ("receipt.png", 21),
        ]
    )

    /// Prefer a sample that satisfies an attached rule so Access preview can show effects.
    static func forAccessPreview(matching pass: GrantRule?) -> SampleMessage {
        guard let pass else { return .invoice }
        let from = Self.haystack(for: pass.fromRules) ?? invoice.from
        let subject = Self.haystack(for: pass.subjectRules) ?? invoice.subject
        let date = Self.date(for: pass.when) ?? invoice.date
        return SampleMessage(
            subject: subject,
            from: from,
            to: invoice.to,
            cc: invoice.cc,
            date: date,
            body: invoice.body,
            attachments: invoice.attachments
        )
    }

    private static func date(for when: RuleWhen?) -> String? {
        guard let when else { return nil }
        if let after = when.after?.trimmingCharacters(in: .whitespacesAndNewlines), !after.isEmpty {
            return "\(String(after.prefix(10)))T12:00:00Z"
        }
        if let before = when.before?.trimmingCharacters(in: .whitespacesAndNewlines), !before.isEmpty {
            return "\(String(before.prefix(10)))T12:00:00Z"
        }
        return nil
    }

    private static func haystack(for rules: [MatchRule]) -> String? {
        guard let rule = rules.first, !rule.value.isEmpty else { return nil }
        switch rule.mode {
        case .exact:
            return rule.value
        case .contains:
            return "Sample \(rule.value) notice"
        case .starts:
            return "\(rule.value) weekly update"
        case .ends:
            // Prefer display-name form so Access preview matches real Apple Mail From lines.
            if rule.value.hasPrefix("@") {
                return "Sample Sender <noreply\(rule.value)>"
            }
            if rule.value.contains("@") {
                return "Sample Sender <\(rule.value)>"
            }
            return "Sample Sender <noreply@\(rule.value)>"
        }
    }

    var mailAttachments: [MailAttachment] {
        attachments.map { MailAttachment(filename: $0.name, byteCount: $0.kb * 1024) }
    }

    var attachmentContentDetail: String {
        "\(attachments.count) files"
    }
}

/// Button-based checkbox — more reliable than Toggle bindings inside NSHostingView.
private struct GrantCheckRow: View {
    let title: String
    let isOn: Bool
    var badge: String? = nil
    var emphasized: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .font(.body)
                Text(title)
                    .font(emphasized ? .caption.weight(.semibold) : .caption)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
