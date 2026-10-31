import AppKit
import MailStore
import SwiftUI

struct MailGentSettingsView: View {
    @Bindable var session: CompanionSession
    @AppStorage(MailGentPreferences.agentMayChangeSourceKey) private var agentMayChangeSource = false
    @AppStorage(MailGentPreferences.agentMayOpenInMailKey) private var agentMayOpenInMail = false
    @AppStorage(MailGentPreferences.agentMayProposeSendKey) private var agentMayProposeSend = false
    @AppStorage(MailGentPreferences.revealAccountsWithNoPlacementsKey) private var revealAccountsWithNoPlacements = false
    @AppStorage(MailGentPreferences.allowConditionalAccessPromptsKey) private var allowConditionalAccessPrompts = false
    @AppStorage(MailGentPreferences.askDecisionCacheEnabledKey) private var askDecisionCacheEnabled = false
    @AppStorage(MailGentPreferences.askDecisionCacheTTLSecondsKey) private var askDecisionCacheTTLSeconds =
        MailGentPreferences.defaultAskDecisionCacheTTLSeconds
    @AppStorage(MailGentPreferences.askDecisionCacheShareScopeKey) private var askDecisionCacheShareScopeRaw =
        AskDecisionCacheShareScope.perAgent.rawValue
    @AppStorage(MailGentPreferences.loopbackPortKey) private var loopbackPort =
        Int(MailGentPreferences.defaultLoopbackPort)
    @AppStorage(MailGentPreferences.auditMaxAgeSecondsKey) private var auditMaxAgeSeconds = 0
    @AppStorage(MailGentPreferences.auditMaxCountKey) private var auditMaxCount = 0
    @AppStorage(MailGentPreferences.auditMaxBytesKey) private var auditMaxBytes = 0
    @AppStorage(MailGentPreferences.proposeSendContextExperimentalKey) private var proposeSendContextExperimental = false
    @AppStorage(MailGentPreferences.secretConstantsEnabledKey) private var secretConstantsEnabled = false
    @State private var confirmClearAll = false
    @State private var confirmClear24h = false
    @State private var vaultRootPath: String = PersonalVaultBookmark.displayPath() ?? ""

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            GrantAccessView(session: session.access)
                .tabItem { Label("Access", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 640)
        .onChange(of: agentMayOpenInMail) { _, _ in
            session.agents.applyAgentMayOpenInMail()
        }
        .onChange(of: agentMayProposeSend) { _, _ in
            session.agents.applyAgentMayProposeSend()
        }
        .onChange(of: proposeSendContextExperimental) { _, _ in
            session.agents.applyProposeSendContextExperimental()
        }
        .onChange(of: revealAccountsWithNoPlacements) { _, _ in
            session.agents.applyRevealAccountsWithNoPlacements()
        }
        .onChange(of: allowConditionalAccessPrompts) { _, _ in
            session.agents.applyConditionalAccessPreference()
        }
        .onChange(of: askDecisionCacheEnabled) { _, _ in
            session.agents.applyAskDecisionCachePreference()
        }
        .onChange(of: askDecisionCacheTTLSeconds) { _, _ in
            session.agents.applyAskDecisionCachePreference()
        }
        .onChange(of: askDecisionCacheShareScopeRaw) { _, _ in
            session.agents.applyAskDecisionCachePreference()
        }
        .onChange(of: loopbackPort) { _, newValue in
            let normalized = Int(MailGentPreferences.normalizedLoopbackPort(newValue))
            if normalized != newValue {
                loopbackPort = normalized
                return
            }
            session.applyLoopbackPort()
        }
        .onChange(of: auditMaxAgeSeconds) { _, _ in session.agents.applyAuditRetention() }
        .onChange(of: auditMaxCount) { _, _ in session.agents.applyAuditRetention() }
        .onChange(of: auditMaxBytes) { _, _ in session.agents.applyAuditRetention() }
        .confirmationDialog(
            "Delete all access logs?",
            isPresented: $confirmClearAll,
            titleVisibility: .visible
        ) {
            Button("Delete all", role: .destructive) {
                session.agents.removeAllAudit()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes the full stored log (\(storedCount) entries, \(storedBytesLabel)). This cannot be undone.")
        }
        .confirmationDialog(
            "Delete logs older than 24 hours?",
            isPresented: $confirmClear24h,
            titleVisibility: .visible
        ) {
            Button("Delete older than 24 hours", role: .destructive) {
                session.agents.removeAuditOlderThan24Hours()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps entries from the last 24 hours. Older rows are removed from the stored log.")
        }
    }

    private var storedCount: Int { session.agents.auditStoredCount }
    private var storedBytesLabel: String {
        AccessLogFormat.bytes(session.agents.auditStoredBytes)
    }

    private var secretConstantsSettingsRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Enable secret constants", isOn: $secretConstantsEnabled)
            Text(
                "Off by default. Agents always see the list_secrets tool; while off it errors as disabled. When on, allowlisted names work for list_secrets and [[mg:name]] in drafts / propose_send. Values stay local — resolved only for you on confirm and in Apple Mail."
            )
            .foregroundStyle(.secondary)
            .font(.callout)
            Button("Manage in Control Center → Secret constants…") {
                DetachedWindowHost.shared.showSecretConstants(session: session)
            }
            .buttonStyle(.link)
        }
        .onChange(of: secretConstantsEnabled) { _, _ in
            session.agents.applySecretConstantsEnabled()
        }
    }

    private var generalTab: some View {
        Form {
            Section("Agents") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Allow agents to change mail source", isOn: $agentMayChangeSource)
                    Text(agentMayChangeSourceHelp)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Allow agents to open messages in Apple Mail", isOn: $agentMayOpenInMail)
                    Text(
                        "Off by default. When on, a paired agent may call MCP open_in_mail to open a granted message in Apple Mail."
                    )
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Allow agents to propose sending mail", isOn: $agentMayProposeSend)
                    Text(
                        "Off by default. When on, a paired agent may call MCP propose_send; you confirm Send, Open in Mail, or Cancel before Apple Mail is touched."
                    )
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }
                secretConstantsSettingsRow
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Reveal accounts with no placements", isOn: $revealAccountsWithNoPlacements)
                    Text(
                        "Off by default. When off, agents do not see Mail identities without a read grant. When on, empty-placement accounts appear in list_accounts and may be used as propose_send From addresses."
                    )
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Allow conditional access prompts", isOn: $allowConditionalAccessPrompts)
                    Text(
                        "Off by default. When on, Grant Desk Ask chips prompt on MCP get (Allow / Block). When off, Ask fields show and act as Off — your Ask settings stay saved and come back when you turn this on again."
                    )
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }
                if allowConditionalAccessPrompts {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Remember Ask decisions", isOn: $askDecisionCacheEnabled)
                        Text(
                            "Off by default. When on, Allow / Block for an Ask field on a message is reused for later gets within the validity window — not a standing grant. New Ask fields still prompt. Pass/Block rules still win first. Timed and forever answers are stored locally; Until MailGent quits stays in memory only."
                        )
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    }
                    if askDecisionCacheEnabled {
                        Picker("Remember for", selection: $askDecisionCacheTTLSeconds) {
                            Text("15 minutes").tag(900)
                            Text("1 hour").tag(3_600)
                            Text("24 hours").tag(86_400)
                            Text("30 days").tag(2_592_000)
                            Text("1 year").tag(31_536_000)
                            Text("Until MailGent quits").tag(0)
                            Text("Forever").tag(MailGentPreferences.askDecisionCacheTTLForever)
                        }
                        Picker("Share with", selection: $askDecisionCacheShareScopeRaw) {
                            Text("This agent only").tag(AskDecisionCacheShareScope.perAgent.rawValue)
                            Text("All agents").tag(AskDecisionCacheShareScope.allAgents.rawValue)
                        }
                        Text(
                            "This agent only keeps Cursor and Grok separate (MCP and CLI on one pairing still share). All agents lets any paired agent reuse the same message decision."
                        )
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    }
                }
                TextField("Loopback MCP port", value: $loopbackPort, format: .number.grouping(.never))
                Text(session.agents.loopbackURL)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .textSelection(.enabled)
                Text("Default 8788. Avoid 8787 — reserved for Cursor OAuth callbacks.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            Section("Access log") {
                LabeledContent("Full log") {
                    Text("\(storedCount) logs · \(storedBytesLabel)")
                        .textSelection(.enabled)
                }
                Picker("Delete entries older than", selection: $auditMaxAgeSeconds) {
                    Text("Never").tag(0)
                    Text("24 hours").tag(86_400)
                    Text("7 days").tag(604_800)
                    Text("30 days").tag(2_592_000)
                    Text("90 days").tag(7_776_000)
                }
                TextField("Maximum number of logs", value: $auditMaxCount, format: .number)
                TextField("Maximum size (bytes)", value: $auditMaxBytes, format: .number)
                if auditMaxBytes > 0 {
                    Text(AccessLogFormat.bytes(auditMaxBytes))
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                Text("0 means no limit. Oldest entries are removed first when a limit is exceeded.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Button("Delete older than 24 hours") {
                    confirmClear24h = true
                }
                .disabled(!session.agents.hasAuditOlderThan24Hours)
                Button("Delete all", role: .destructive) {
                    confirmClearAll = true
                }
                .disabled(storedCount == 0)
            }
            Section("Experimental") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Propose-send context thread", isOn: $proposeSendContextExperimental)
                    Text(
                        "Off by default. When on, propose_send may include an optional context timeline (vault + mail) beside the draft. Experimental — schema and UI may change."
                    )
                    .foregroundStyle(.secondary)
                    .font(.callout)
                }
                if proposeSendContextExperimental {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Personal vault root") {
                            Text(vaultRootPath.isEmpty ? "Not set" : vaultRootPath)
                                .foregroundStyle(vaultRootPath.isEmpty ? .secondary : .primary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        HStack {
                            Button("Choose…") { choosePersonalVaultRoot() }
                            if !vaultRootPath.isEmpty {
                                Button("Clear", role: .destructive) {
                                    PersonalVaultBookmark.clear()
                                    vaultRootPath = ""
                                }
                            }
                        }
                        Text(
                            "MailGent reads vault files under this folder when resolving context events. Required for vault rows; mail rows still use the store."
                        )
                        .foregroundStyle(.secondary)
                        .font(.callout)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            vaultRootPath = PersonalVaultBookmark.displayPath() ?? ""
        }
    }

    private func choosePersonalVaultRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Select your Personal vault root for propose-send context."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try PersonalVaultBookmark.save(url)
            vaultRootPath = url.path
        } catch {
            vaultRootPath = PersonalVaultBookmark.displayPath() ?? ""
        }
    }

    private var agentMayChangeSourceHelp: String {
        #if DEBUG
        "Off by default. When on, a paired agent may call MCP set_source to switch fixture ↔ live Mail."
        #else
        "Off by default. When on, a paired agent may call MCP set_source (live Mail only in Release builds)."
        #endif
    }
}
