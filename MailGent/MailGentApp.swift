import SwiftUI

@main
struct MailGentApp: App {
    @State private var session = CompanionSession()

    init() {
        MailGentLog.trace("MailGent launched pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    var body: some Scene {
        MenuBarExtra("MailGent", systemImage: "tray.full") {
            MenuBarStatus(session: session)
        }
        .menuBarExtraStyle(.window)

        Settings {
            GrantAccessView(session: session.access)
                .frame(minWidth: 420, minHeight: 240)
        }
    }
}
