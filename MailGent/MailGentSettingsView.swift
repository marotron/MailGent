import SwiftUI

struct MailGentSettingsView: View {
    @Bindable var session: CompanionSession
    @AppStorage(MailGentPreferences.agentMayChangeSourceKey) private var agentMayChangeSource = false
    @AppStorage(MailGentPreferences.loopbackPortKey) private var loopbackPort =
        Int(MailGentPreferences.defaultLoopbackPort)
    @AppStorage(MailGentPreferences.auditMaxAgeSecondsKey) private var auditMaxAgeSeconds = 0
    @AppStorage(MailGentPreferences.auditMaxCountKey) private var auditMaxCount = 0
    @AppStorage(MailGentPreferences.auditMaxBytesKey) private var auditMaxBytes = 0
    @State private var confirmClearAll = false
    @State private var confirmClear24h = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            GrantAccessView(session: session.access)
                .tabItem { Label("Access", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 600)
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

    private var generalTab: some View {
        Form {
            Section("Agents") {
                Toggle("Allow agents to change mail source", isOn: $agentMayChangeSource)
                Text(
                    "Off by default. When on, a paired agent may call MCP set_source to switch fixture ↔ live Mail."
                )
                .foregroundStyle(.secondary)
                .font(.callout)
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
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
