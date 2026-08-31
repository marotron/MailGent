import MailStore
import SwiftUI

/// Lean grant desk: Scope (placements) + Access (per-placement field caps + sample preview).
struct GrantDeskView: View {
    @Bindable var session: CompanionSession
    @State private var tab: Tab = .scope
    @State private var expandedInfo: String?

    enum Tab: String, CaseIterable, Identifiable {
        case scope = "Scope"
        case access = "Access"
        case privacy = "Privacy"
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
                .frame(maxWidth: 300)
                .accessibilityLabel("Grant desk section")

                Spacer(minLength: 8)
                editModeControls
            }

            switch tab {
            case .scope:
                scopePane
            case .access:
                accessPane
            case .privacy:
                LeakGuardPrivacyPane(session: session, expandedInfo: $expandedInfo)
            }

            Spacer(minLength: 0)
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
            LeakGuardMasterRow(
                isOn: Binding(
                    get: { session.agents.leakGuardEnabled },
                    set: { session.agents.setLeakGuardEnabled($0) }
                ),
                isEditing: isEditing,
                peerTab: "Privacy",
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
                    }
                    .frame(maxHeight: 340)
                }
            }

            GrantDeskCard(title: "Narrow scope", expandedInfo: $expandedInfo) {
                VStack(alignment: .leading, spacing: 8) {
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
                }
            }

            if isEditing, !session.agents.grantRows.isEmpty {
                Button("Clear all grants", role: .destructive) {
                    session.agents.clearGrants()
                }
            }

            if !session.agents.allowGrants.isEmpty {
                Text("Detectors & custom rules → Privacy tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                    VStack(alignment: .leading, spacing: 10) {
                        fieldEditor(for: selected)
                        Divider()
                        Text("Preview")
                            .font(.subheadline.weight(.semibold))
                        previewCaption(for: selected)
                        AgentAccessPreview(session: session, grant: selected)
                    }
                }
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
        }
    }

    private var scopeHintRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("Check placements to allow. Field badges = Access caps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GrantDeskInfoButton(topic: .grantFieldBadges, expandedInfo: $expandedInfo, size: .small)
                Text("· Leak guard")
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
            Text("Fields apply only to this allow.")
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
                   session.agents.hasAccountWideGrant(accountID: account.id),
                   !session.agents.draftDenyMode {
                    scopeBadgeRow(
                        fields: grant.fields,
                        accountID: account.id,
                        placement: nil,
                        showsLeakGuard: true,
                        interactive: isEditing
                    ) { keyPath in
                        session.agents.toggleAllowField(
                            accountID: account.id,
                            placement: nil,
                            keyPath: keyPath
                        )
                    }
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
                    if !session.agents.draftDenyMode,
                       let edit = accountWide
                        ? session.agents.allowGrant(accountID: account.id, placement: nil)
                        : mbGrant {
                        scopeBadgeRow(
                            fields: edit.fields,
                            accountID: account.id,
                            placement: accountWide ? nil : mailbox.placement,
                            showsLeakGuard: allowed && !accountWide,
                            interactive: isEditing
                        ) { keyPath in
                            session.agents.toggleAllowField(
                                accountID: account.id,
                                placement: accountWide ? nil : mailbox.placement,
                                keyPath: keyPath
                            )
                        }
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
        return VStack(alignment: .leading, spacing: 4) {
            Text(pathLabel(grant))
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.leading)
            HStack(spacing: 4) {
                GrantFieldBadgeRow(
                    fields: grant.fields,
                    interactive: false
                )
                if shieldState != .off {
                    LeakGuardShieldChip(state: shieldState)
                }
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
            GrantFieldBadgeRow(fields: fields, interactive: interactive, onToggle: onToggle)
            if showsLeakGuard {
                LeakGuardScopeControls(
                    session: session,
                    accountID: accountID,
                    placement: placement,
                    isEditing: interactive,
                    expandedInfo: $expandedInfo
                )
            }
        }
    }
}

// MARK: - Access sample preview (hatch)

private struct AgentAccessPreview: View {
    let session: CompanionSession
    let grant: Grant

    private let sample = SampleMessage.invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MessageAccessCard(
                session: session,
                ref: sampleRef,
                showsFieldBadges: false,
                attachmentContentDetail: sample.attachmentContentDetail
            )
            if let rules = sampleRef.sanitizedRules, !rules.isEmpty {
                Text("Sanitized: \(rules.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if AccessLogFormat.showsSanitizedLegend(for: [sampleRef]) {
                SanitizedFieldsLegend()
            }
            LockedFieldsLegend()
        }
        .id(session.agents.leakGuardRevision)
    }

    private var sampleRef: AuditMessageRef {
        let scanPlacement = grant.placement ?? "INBOX"
        let leakGuard = OutboundLeakGuard(policy: session.agents.leakGuardPolicy)
        let subjectField = leakGuard.sanitize(
            text: sample.subject,
            field: .subject,
            accountID: grant.accountID,
            placement: scanPlacement,
            fieldGranted: grant.fields.subject
        )
        let bodyField = leakGuard.sanitize(
            text: sample.body,
            field: .body,
            accountID: grant.accountID,
            placement: scanPlacement,
            fieldGranted: grant.fields.body
        )
        let disclosed = Array(Set(subjectField.disclosedRules + bodyField.disclosedRules)).sorted()
        return AuditMessageRef(
            accountID: grant.accountID,
            placement: grant.placement ?? "all mailboxes",
            id: "sample",
            subject: displayText(subjectField, granted: grant.fields.subject),
            from: sample.from,
            date: sample.date,
            to: sample.to,
            cc: sample.cc,
            bodySnippet: displayText(bodyField, granted: grant.fields.body),
            subjectAccess: grant.fields.subject ? subjectField.access.auditBodyAccess : .notGranted,
            bodyAccess: grant.fields.body ? bodyField.access.auditBodyAccess : .notGranted,
            subjectOriginal: subjectField.original != subjectField.text ? subjectField.original : nil,
            bodyOriginal: bodyField.original != bodyField.text ? bodyField.original : nil,
            sanitizedRules: disclosed.isEmpty ? nil : disclosed,
            stealth: subjectField.stealth || bodyField.stealth,
            fields: grant.fields,
            attachments: grant.fields.attachmentMetadata ? sample.mailAttachments : []
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
