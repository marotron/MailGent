import SwiftUI

@main
struct MailGentApp: App {
    @State private var session = MailAccessSession()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
        }
        .defaultSize(width: 520, height: 420)
    }
}
