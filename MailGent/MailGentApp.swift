import SwiftUI

@main
struct MailGentApp: App {
    @State private var session = PrototypeReadSession()

    var body: some Scene {
        MenuBarExtra("MailGent", systemImage: "tray.full") {
            PrototypeMenuBar(session: session)
        }
        .menuBarExtraStyle(.window)

        Window("MailGent", id: "companion") {
            PrototypeReadRoot(session: session)
        }
        .defaultSize(width: 980, height: 640)

        Settings {
            GrantAccessView(session: session.access)
                .frame(minWidth: 420, minHeight: 240)
        }
    }
}
