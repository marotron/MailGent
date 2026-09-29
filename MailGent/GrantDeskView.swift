import MailStore
import SwiftUI

/// Lean grant desk: Scope (placements) + Passes + Access (field caps + sample preview).
struct GrantDeskView: View {
    @Bindable var session: CompanionSession
    @State private var tab: Tab = .scope
    @State private var selectedPassID: String?

    enum Tab: String, CaseIterable, Identifiable {
        case scope = "Scope"
        case passes = "Passes"
        case access = "Access"
        var id: String { rawValue }
    }

    private var isEditing: Bool { session.agents.isEditingGrants }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Picker("", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .accessibilityLabel("Grant desk section")

                Spacer(minLength: 8)
                editModeControls
            }

            Group {
                switch tab {
                case .scope:
                    scopePane
                case .passes:
                    PassDeskPane(
                        session: session,
                        selectedPassID: $selectedPassID,
                        isEditing: isEditing
                    )
                case .access:
                    accessPane
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(16)
        .frame(minWidth: 700, minHeight: 560)
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
            Text("Check placements to allow. Click field badges to toggle Access caps (default: headers only). Attach Passes as green chips (Edit first).")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Narrow From (optional)", text: Binding(
                get: { session.agents.draftFromFilter },
                set: { session.agents.draftFromFilter = $0 }
            ))
                .textFieldStyle(.roundedBorder)
                .disabled(!isEditing)
            TextField("On/after date ISO8601 (optional)", text: Binding(
                get: { session.agents.draftDateStart },
                set: { session.agents.draftDateStart = $0 }
            ))
                .textFieldStyle(.roundedBorder)
                .disabled(!isEditing)
            GrantCheckRow(
                title: "Deny carve-out mode",
                isOn: session.agents.draftDenyMode
            ) {
                session.agents.draftDenyMode.toggle()
            }
            .disabled(!isEditing)

            if session.scanCatalog.isEmpty {
                Text("Index accounts first.")
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(session.scanCatalog) { account in
                            accountBlock(account)
                        }
                    }
                    .padding(.vertical, 2)
                    .id(session.agents.grantRevision)
                }
                .frame(maxHeight: .infinity)
            }

            if isEditing, !session.agents.grantRows.isEmpty {
                Button("Clear all grants", role: .destructive) {
                    session.agents.clearGrants()
                }
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
                            AgentAccessPreview(session: session, grant: selected)
                                .id("\(session.agents.grantRevision)-\(session.agents.passRevision)-\(AgentBridge.accessKey(for: selected))")
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
                        let passes = session.agents.enabledPasses(
                            accountID: grant.accountID,
                            placement: grant.placement
                        )
                        Button {
                            session.agents.selectAccessGrant(grant)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pathLabel(grant))
                                    .font(.caption.weight(.semibold))
                                    .multilineTextAlignment(.leading)
                                HStack(spacing: 4) {
                                    GrantFieldBadgeRow(
                                        fields: grant.fields,
                                        interactive: false
                                    )
                                    if !passes.isEmpty {
                                        AccessPassNickChip(nicks: passes.map(\.nick).joined())
                                    }
                                }
                            }
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

    private func fieldEditor(for grant: Grant) -> some View {
        let fields = grant.fields
        return VStack(alignment: .leading, spacing: 6) {
            Text(pathLabel(grant))
                .font(.headline)
            Text("Fields apply only to this allow. Passes can green-light more fields on match.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
            HStack(spacing: 6) {
                fieldBadge("Subject", fields.subject, grant, \.subject, systemImage: "text.alignleft")
                fieldBadge("From", fields.from, grant, \.from, systemImage: "envelope")
                fieldBadge("To", fields.to, grant, \.to, systemImage: "envelope")
                fieldBadge("Cc", fields.cc, grant, \.cc, systemImage: "person.2")
                fieldBadge("Date & Time", fields.date, grant, \.date, systemImage: "calendar")
            }
            .disabled(!isEditing)
            Text("Content")
                .font(.caption.weight(.semibold))
                .padding(.top, 4)
            HStack(spacing: 6) {
                fieldBadge(
                    "Body / snippet",
                    fields.body,
                    grant,
                    \.body,
                    systemImage: "text.alignleft"
                )
                fieldBadge(
                    "Attachment names",
                    fields.attachmentMetadata,
                    grant,
                    \.attachmentMetadata,
                    systemImage: "paperclip"
                )
                fieldBadge(
                    "Attachment content",
                    fields.attachmentContent,
                    grant,
                    \.attachmentContent,
                    systemImage: "paperclip"
                )
            }
            .disabled(!isEditing)

            VStack(alignment: .leading, spacing: 4) {
                Text("Passes on this placement")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if session.agents.passDefinitions.isEmpty {
                    Text("No passes yet — create one on Passes tab.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    PassToggleChips(
                        session: session,
                        accountID: grant.accountID,
                        placement: grant.placement,
                        isEditing: isEditing && !session.agents.draftDenyMode,
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
        _ isOn: Bool,
        _ grant: Grant,
        _ keyPath: WritableKeyPath<GrantFields, Bool>,
        systemImage: String? = nil
    ) -> some View {
        Button {
            session.agents.toggleAllowField(
                accountID: grant.accountID,
                placement: grant.placement,
                keyPath: keyPath
            )
        } label: {
            GrantFieldChip(title: title, isOn: isOn, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(!isEditing || session.agents.draftDenyMode)
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
                .disabled(!isEditing || session.agents.draftDenyMode)
                if let grant = session.agents.allowGrant(accountID: account.id, placement: nil),
                   !session.agents.draftDenyMode {
                    GrantFieldBadgeRow(fields: grant.fields, interactive: isEditing) { keyPath in
                        session.agents.toggleAllowField(
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
                        isOn: session.agents.draftDenyMode ? denied : allowed,
                        badge: denied ? "deny" : nil
                    ) {
                        session.agents.setMailbox(
                            accountID: account.id,
                            placement: mailbox.placement,
                            enabled: session.agents.draftDenyMode ? !denied : !allowed
                        )
                    }
                    .disabled(
                        !isEditing || (!session.agents.draftDenyMode && accountWide)
                    )
                    if !session.agents.draftDenyMode, allowed,
                       let fields = session.agents.effectiveAllowFields(
                           accountID: account.id,
                           placement: mailbox.placement
                       ) {
                        GrantFieldBadgeRow(fields: fields, interactive: isEditing) { keyPath in
                            session.agents.toggleAllowField(
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

    private func pathLabel(_ grant: Grant) -> String {
        let account = session.scanCatalog.first { $0.id == grant.accountID }
        let name = account?.displayName
            ?? CompanionAccounts.label(grant.accountID)
        if let placement = grant.placement {
            return "\(name) / \(placement)"
        }
        return "\(name) · all mailboxes"
    }
}

// MARK: - Access sample preview (hatch + pass green lights)

private struct AccessPassNickChip: View {
    let nicks: String

    private static let passGreen = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255)
    private static let passSoft = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255).opacity(0.12)
    private static let passBorder = Color(red: 143 / 255, green: 209 / 255, blue: 160 / 255)

    var body: some View {
        Text("✓\(nicks)")
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(Self.passGreen)
            .tracking(0.4)
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(Self.passSoft, in: Capsule())
            .overlay(Capsule().strokeBorder(Self.passBorder, lineWidth: 0.5))
    }
}

private struct AgentAccessPreview: View {
    let session: CompanionSession
    let grant: Grant

    private static let passGreen = Color(red: 36 / 255, green: 138 / 255, blue: 61 / 255)

    private var attached: [Pass] {
        session.agents.enabledPasses(accountID: grant.accountID, placement: grant.placement)
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
        guard let agentID = session.agents.agent?.id else { return grant.fields }
        return PassEngine.upgrade(
            base: grant.fields,
            message: indexedSample,
            agentID: agentID,
            passes: session.agents.passDefinitions,
            enablements: session.agents.passes.allEnablements()
        )
    }

    private var firedPasses: [Pass] {
        guard let agentID = session.agents.agent?.id else { return [] }
        var current = grant.fields
        var fired: [Pass] = []
        for pass in attached {
            let next = PassEngine.upgrade(
                base: current,
                message: indexedSample,
                agentID: agentID,
                passes: [pass],
                enablements: session.agents.passes.allEnablements()
            )
            if next != current {
                fired.append(pass)
                current = next
            }
        }
        return fired
    }

    private func viaPassNick(for keyPath: KeyPath<GrantFields, Bool>) -> String? {
        guard !grant.fields[keyPath: keyPath], effectiveFields[keyPath: keyPath],
              let pass = firedPasses.first(where: { $0.fields[keyPath: keyPath] })
        else { return nil }
        return pass.nick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MessageAccessCard(
                session: session,
                ref: sampleRef,
                showsFieldBadges: false,
                attachmentContentDetail: sample.attachmentContentDetail,
                bodyViaPassNick: viaPassNick(for: \.body),
                attachmentInfoViaPassNick: viaPassNick(for: \.attachmentMetadata),
                attachmentContentViaPassNick: viaPassNick(for: \.attachmentContent)
            )

            ForEach(firedPasses) { pass in
                Text(passNote(pass))
                    .font(.system(size: 10))
                    .foregroundStyle(Self.passGreen)
            }

            if !attached.isEmpty, firedPasses.isEmpty {
                Text("Attached passes did not match this sample (or their fields are already covered).")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if hasLockedFields {
                LockedFieldsLegend()
            }
        }
    }

    private var hasLockedFields: Bool {
        let f = effectiveFields
        return !f.subject || !f.from || !f.to || !f.cc || !f.date
            || !f.body || !f.attachmentMetadata || !f.attachmentContent
    }

    private func passNote(_ pass: Pass) -> String {
        let labels = greenLitLabels(pass: pass, base: grant.fields)
        let joined = labels.isEmpty ? "fields" : labels.joined(separator: ", ")
        return "PASS — \(pass.name) (✓ \(pass.nick)) green-lit \(joined)."
    }

    private func greenLitLabels(pass: Pass, base: GrantFields) -> [String] {
        var labels: [String] = []
        if pass.fields.body && !base.body { labels.append("body") }
        if pass.fields.attachmentMetadata && !base.attachmentMetadata { labels.append("attachment names") }
        if pass.fields.attachmentContent && !base.attachmentContent { labels.append("attachment content") }
        if pass.fields.subject && !base.subject { labels.append("subject") }
        if pass.fields.from && !base.from { labels.append("from") }
        if pass.fields.to && !base.to { labels.append("to") }
        if pass.fields.cc && !base.cc { labels.append("cc") }
        if pass.fields.date && !base.date { labels.append("date") }
        return labels
    }

    private var sampleRef: AuditMessageRef {
        let fields = effectiveFields
        return AuditMessageRef(
            accountID: grant.accountID,
            placement: grant.placement ?? "all mailboxes",
            id: "sample",
            subject: sample.subject,
            from: sample.from,
            date: sample.date,
            to: sample.to,
            cc: sample.cc,
            bodySnippet: sample.body,
            bodyAccess: fields.body ? .granted : .notGranted,
            fields: fields,
            attachments: fields.attachmentMetadata ? sample.mailAttachments : []
        )
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
        body: "Hi,\n\nAttached is your March invoice ($48.00).\nCard ending 4412 was charged.\n\nThanks,\nHostCo billing",
        attachments: [
            ("invoice-4412.pdf", 82),
            ("receipt.png", 21),
        ]
    )

    /// Prefer a sample that satisfies an attached pass so Access preview can show green lights.
    static func forAccessPreview(matching pass: Pass?) -> SampleMessage {
        guard let pass else { return .invoice }
        let from = Self.haystack(for: pass.fromRules) ?? invoice.from
        let subject = Self.haystack(for: pass.subjectRules) ?? invoice.subject
        return SampleMessage(
            subject: subject,
            from: from,
            to: invoice.to,
            cc: invoice.cc,
            date: invoice.date,
            body: invoice.body,
            attachments: invoice.attachments
        )
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
            if rule.value.contains("@") { return rule.value }
            return "noreply@\(rule.value)"
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
