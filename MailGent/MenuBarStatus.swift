import AppKit
import SwiftUI

struct MenuBarStatus: View {
    @Bindable var session: CompanionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MailGent")
                .font(.headline)
            LabeledContent("Access") {
                Text(session.mailAccessGranted ? "Granted" : "Denied")
                    .foregroundStyle(session.mailAccessGranted ? .green : .orange)
            }
            LabeledContent("Last ingest") {
                Text(session.lastIngestAt?.formatted(date: .omitted, time: .shortened) ?? "—")
            }
            LabeledContent("New") {
                Text("\(session.lastNewCount)")
            }
            LabeledContent("Source") {
                Text(session.source.title)
            }
            Divider()
            Button("Open Companion") {
                session.openHome()
                DetachedWindowHost.shared.showCompanion(session: session)
            }
            .keyboardShortcut(.defaultAction)
            Button("Grant access…") {
                DetachedWindowHost.shared.showAccess(session: session.access)
            }
            Button("Quit MailGent") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear(perform: session.refreshAccess)
    }
}
