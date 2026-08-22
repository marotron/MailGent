import SwiftUI

struct MailGentSettingsView: View {
    @Bindable var session: CompanionSession
    @AppStorage(MailGentPreferences.agentMayChangeSourceKey) private var agentMayChangeSource = false
    @AppStorage(MailGentPreferences.auditMaxAgeSecondsKey) private var auditMaxAgeSeconds = 0
    @AppStorage(MailGentPreferences.auditMaxCountKey) private var auditMaxCount = 0
    @AppStorage(MailGentPreferences.auditMaxBytesKey) private var auditMaxBytes = 0

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            GrantAccessView(session: session.access)
                .tabItem { Label("Access", systemImage: "lock.shield") }
        }
        .frame(width: 480, height: 560)
        .onChange(of: auditMaxAgeSeconds) { _, _ in session.agents.applyAuditRetention() }
        .onChange(of: auditMaxCount) { _, _ in session.agents.applyAuditRetention() }
        .onChange(of: auditMaxBytes) { _, _ in session.agents.applyAuditRetention() }
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
            }
            Section("Access log") {
                LabeledContent("Full log") {
                    Text("\(session.agents.auditStoredCount) logs · \(AccessLogFormat.bytes(session.agents.auditStoredBytes))")
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
                Text("0 means no limit. Oldest entries are removed first when a limit is exceeded. The Access log window can also delete all entries or those older than 24 hours.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
