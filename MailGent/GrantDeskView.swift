import MailStore
import SwiftUI

/// Lean grant desk: Scope (placements) + Access (per-placement field caps + sample preview).
struct GrantDeskView: View {
    @Bindable var session: CompanionSession
    @State private var tab: Tab = .scope
    /// Hatch+label for headers; censor bars for body / attachment bytes.
    @State private var previewStyle: DeniedPreviewStyle = .mixed

    enum Tab: String, CaseIterable, Identifiable {
        case scope = "Scope"
        case access = "Access"
        var id: String { rawValue }
    }

    enum DeniedPreviewStyle: String, CaseIterable, Identifiable {
        case hatch = "Hatch"
        case censor = "Censor"
        case mixed = "Mixed"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Grant desk")
                    .font(.title2.weight(.semibold))
                Spacer()
                if let agent = session.agents.agent {
                    Text("\(agent.name) · \(agent.trustClass.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Tab", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            switch tab {
            case .scope:
                scopePane
            case .access:
                accessPane
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 480)
        .id(session.agents.grantRevision)
    }

    private var scopePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Check placements to allow. Click field badges to toggle Access caps (default: headers only).")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Narrow From (optional)", text: Binding(
                get: { session.agents.draftFromFilter },
                set: { session.agents.draftFromFilter = $0 }
            ))
                .textFieldStyle(.roundedBorder)
            TextField("On/after date ISO8601 (optional)", text: Binding(
                get: { session.agents.draftDateStart },
                set: { session.agents.draftDateStart = $0 }
            ))
                .textFieldStyle(.roundedBorder)
            GrantCheckRow(
                title: "Deny carve-out mode",
                isOn: session.agents.draftDenyMode
            ) {
                session.agents.draftDenyMode.toggle()
            }

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
                }
            }

            if !session.agents.grantRows.isEmpty {
                Button("Clear all grants", role: .destructive) {
                    session.agents.clearGrants()
                }
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
                        .frame(width: 180, alignment: .top)
                    VStack(alignment: .leading, spacing: 10) {
                        fieldEditor(for: selected)
                        Divider()
                        HStack {
                            Text("What this means")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Picker("Style", selection: $previewStyle) {
                                ForEach(DeniedPreviewStyle.allCases) { style in
                                    Text(style.rawValue).tag(style)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 220)
                        }
                        Text("Sample message under this placement’s caps. Denied fields use \(previewStyle.rawValue.lowercased()) treatment.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        AgentAccessPreview(
                            fields: selected.fields,
                            style: previewStyle,
                            pathLabel: pathLabel(selected)
                        )
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
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pathLabel(grant))
                                    .font(.caption.weight(.semibold))
                                    .multilineTextAlignment(.leading)
                                FieldBadgeRow(
                                    fields: grant.fields,
                                    interactive: false
                                )
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
        }
    }

    private func fieldEditor(for grant: Grant) -> some View {
        let fields = grant.fields
        return VStack(alignment: .leading, spacing: 6) {
            Text(pathLabel(grant))
                .font(.headline)
            Text("Fields apply only to this allow.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Presets")
                .font(.caption.weight(.semibold))
                .padding(.top, 4)
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

            Text("Envelope")
                .font(.caption.weight(.semibold))
                .padding(.top, 4)
            fieldToggle("Subject", fields.subject, grant, \.subject)
            fieldToggle("From", fields.from, grant, \.from)
            fieldToggle("To", fields.to, grant, \.to)
            fieldToggle("Date", fields.date, grant, \.date)
            Text("Content")
                .font(.caption.weight(.semibold))
                .padding(.top, 4)
            fieldToggle("Body / snippet", fields.body, grant, \.body)
            fieldToggle("Attachment names", fields.attachmentMetadata, grant, \.attachmentMetadata)
            fieldToggle("Attachment content", fields.attachmentContent, grant, \.attachmentContent)
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

    private func fieldToggle(
        _ title: String,
        _ isOn: Bool,
        _ grant: Grant,
        _ keyPath: WritableKeyPath<GrantFields, Bool>
    ) -> some View {
        GrantCheckRow(title: title, isOn: isOn) {
            session.agents.toggleAllowField(
                accountID: grant.accountID,
                placement: grant.placement,
                keyPath: keyPath
            )
        }
        .disabled(session.agents.draftDenyMode)
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
                .disabled(session.agents.draftDenyMode)
                if let grant = session.agents.allowGrant(accountID: account.id, placement: nil),
                   !session.agents.draftDenyMode {
                    FieldBadgeRow(fields: grant.fields, interactive: true) { keyPath in
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
                        !session.agents.draftDenyMode && accountWide
                    )
                    if !session.agents.draftDenyMode,
                       let edit = accountWide
                        ? session.agents.allowGrant(accountID: account.id, placement: nil)
                        : mbGrant {
                        FieldBadgeRow(fields: edit.fields, interactive: true) { keyPath in
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

// MARK: - Field badges

private struct FieldBadgeRow: View {
    let fields: GrantFields
    var interactive: Bool = false
    var onToggle: ((WritableKeyPath<GrantFields, Bool>) -> Void)? = nil

    private static let items: [(String, WritableKeyPath<GrantFields, Bool>)] = [
        ("subj", \.subject),
        ("from", \.from),
        ("to", \.to),
        ("date", \.date),
        ("body", \.body),
        ("att", \.attachmentMetadata),
        ("bytes", \.attachmentContent),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.items, id: \.0) { label, keyPath in
                let on = fields[keyPath: keyPath]
                if interactive, let onToggle {
                    Button {
                        onToggle(keyPath)
                    } label: {
                        badge(label, on: on)
                    }
                    .buttonStyle(.plain)
                    .help("Toggle \(label)")
                } else {
                    badge(label, on: on)
                }
            }
        }
    }

    private func badge(_ label: String, on: Bool) -> some View {
        Text(label)
            .font(.system(size: 8, weight: on ? .medium : .regular))
            .foregroundStyle(on ? Color.accentColor : Color.secondary.opacity(0.55))
            .padding(.horizontal, 4)
            .frame(height: 12)
            .background(
                Capsule()
                    .fill(on ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        on ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.2),
                        lineWidth: 0.5
                    )
            )
            .strikethrough(!on, color: Color.secondary.opacity(0.45))
    }
}

// MARK: - Access sample preview (hatch / censor)

private struct AgentAccessPreview: View {
    let fields: GrantFields
    let style: GrantDeskView.DeniedPreviewStyle
    let pathLabel: String

    private let sample = SampleMessage.invoice

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Sample")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(pathLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            previewRow("Subject", sample.subject, fields.subject, treatment: headerTreatment)
            previewRow("From", sample.from, fields.from, treatment: headerTreatment)
            previewRow("To", sample.to, fields.to, treatment: headerTreatment)
            previewRow("Date", sample.date, fields.date, treatment: headerTreatment)
            Text("Body")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            deniedOrVisible(
                granted: fields.body,
                treatment: bodyTreatment,
                visible: {
                    Text(sample.body)
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                },
                placeholder: sample.body
            )
            ForEach(sample.attachments, id: \.name) { att in
                HStack {
                    deniedOrVisible(
                        granted: fields.attachmentMetadata,
                        treatment: headerTreatment,
                        visible: {
                            Text("\(att.name) · \(att.kb) KB")
                                .font(.caption)
                        },
                        placeholder: att.name
                    )
                    Spacer()
                    deniedOrVisible(
                        granted: fields.attachmentContent,
                        treatment: bodyTreatment,
                        visible: { Text("content").font(.caption2) },
                        placeholder: "content"
                    )
                }
                .padding(6)
                .background(Color.secondary.opacity(0.05))
                .cornerRadius(6)
            }
            Text(legend)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.secondary.opacity(0.2)))
    }

    private var headerTreatment: DeniedTreatment {
        switch style {
        case .hatch, .mixed: return .hatch
        case .censor: return .censor
        }
    }

    private var bodyTreatment: DeniedTreatment {
        switch style {
        case .censor, .mixed: return .censor
        case .hatch: return .hatch
        }
    }

    private var legend: String {
        switch style {
        case .hatch: return "Hatched + “not granted” = agent cannot read"
        case .censor: return "Black bars = redacted from agent"
        case .mixed: return "Headers: hatch · Body/bytes: censor bars"
        }
    }

    private func previewRow(
        _ label: String,
        _ value: String,
        _ granted: Bool,
        treatment: DeniedTreatment
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)
            deniedOrVisible(
                granted: granted,
                treatment: treatment,
                visible: { Text(value).font(.caption) },
                placeholder: value
            )
        }
    }

    @ViewBuilder
    private func deniedOrVisible<V: View>(
        granted: Bool,
        treatment: DeniedTreatment,
        @ViewBuilder visible: () -> V,
        placeholder: String
    ) -> some View {
        if granted {
            visible()
        } else {
            switch treatment {
            case .hatch:
                HatchDeniedLabel(placeholder: placeholder)
            case .censor:
                CensorBar(placeholder: placeholder)
            }
        }
    }
}

private enum DeniedTreatment {
    case hatch
    case censor
}

private struct HatchDeniedLabel: View {
    let placeholder: String

    var body: some View {
        Text(placeholder)
            .font(.caption)
            .foregroundStyle(.clear)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .padding(.horizontal, 4)
            .background {
                HatchPattern()
                    .opacity(0.9)
            }
            .overlay {
                Text("not granted")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct CensorBar: View {
    let placeholder: String

    var body: some View {
        Text(placeholder)
            .font(.caption)
            .foregroundStyle(.clear)
            .frame(maxWidth: .infinity, minHeight: 16, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .accessibilityLabel("Redacted")
    }
}

private struct HatchPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 5
            var path = Path()
            let extent = size.width + size.height
            var x: CGFloat = -size.height
            while x < extent {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                x += spacing
            }
            context.stroke(
                path,
                with: .color(Color.secondary.opacity(0.45)),
                lineWidth: 1
            )
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color.secondary.opacity(0.08))
            )
        }
    }
}

private struct SampleMessage {
    let subject: String
    let from: String
    let to: String
    let date: String
    let body: String
    let attachments: [(name: String, kb: Int)]

    static let invoice = SampleMessage(
        subject: "Invoice #4412 — March hosting",
        from: "billing@hostco.example",
        to: "you@yahoo.com",
        date: "2026-03-12T09:14:00Z",
        body: "Hi,\n\nAttached is your March invoice ($48.00).\nCard ending 4412 was charged.\n\nThanks,\nHostCo billing",
        attachments: [
            ("invoice-4412.pdf", 82),
            ("receipt.png", 21),
        ]
    )
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
