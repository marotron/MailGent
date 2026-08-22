import SwiftUI

@main
struct MailGentApp: App {
    @State private var session = CompanionSession()

    init() {
        MailGentLog.trace("MailGent launched pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarStatus(session: session)
        } label: {
            MenuBarIconLabel(agents: session.agents, source: session.source)
        }
        .menuBarExtraStyle(.window)

        Settings {
            MailGentSettingsView(session: session)
        }
    }
}
