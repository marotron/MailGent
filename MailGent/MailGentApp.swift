import SwiftUI

@main
struct MailGentApp: App {
    @State private var session = PrototypeDraftSession()

    init() {
        MailGentLog.trace("MailGent PROTOTYPE draft-outbound pid=\(ProcessInfo.processInfo.processIdentifier)")
    }

    var body: some Scene {
        MenuBarExtra("MailGent", systemImage: "tray.full") {
            PrototypeDraftMenuBar()
        }
        .menuBarExtraStyle(.window)

        Window("Draft outbound prototype", id: "draft-prototype") {
            PrototypeDraftRoot(session: session)
        }
        .defaultSize(width: 1020, height: 680)
    }
}
