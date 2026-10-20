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
                .onAppear {
                    #if DEBUG
                    AskSandboxLaunch.openIfRequested()
                    #endif
                }
        } label: {
            MenuBarIconLabel(agents: session.agents, source: session.source)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About MailGent") {
                    DetachedWindowHost.shared.showAbout()
                }
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    DetachedWindowHost.shared.showSettings(session: session)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

#if DEBUG
@MainActor
private enum AskSandboxLaunch {
    private static var opened = false

    static func openIfRequested() {
        guard !opened, ProcessInfo.processInfo.environment["MAILGENT_SHOW_ASK_SANDBOX"] == "1" else { return }
        opened = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            DetachedWindowHost.shared.showAskLayoutSandbox()
        }
    }
}
#endif
