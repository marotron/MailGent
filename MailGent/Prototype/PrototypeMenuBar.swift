import AppKit
import SwiftUI

struct PrototypeMenuBar: View {
    @Bindable var session: PrototypeReadSession
    @Environment(\.openWindow) private var openWindow

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
                openWindow(id: "companion")
            }
            .keyboardShortcut(.defaultAction)
            SettingsLink {
                Text("Grant access…")
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
