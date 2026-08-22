import SwiftUI

struct MailGentSettingsView: View {
    @Bindable var session: CompanionSession
    @AppStorage(MailGentPreferences.agentMayChangeSourceKey) private var agentMayChangeSource = false

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("General", systemImage: "gearshape") }
            GrantAccessView(session: session.access)
                .tabItem { Label("Access", systemImage: "lock.shield") }
        }
        .frame(minWidth: 480, minHeight: 280)
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
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
