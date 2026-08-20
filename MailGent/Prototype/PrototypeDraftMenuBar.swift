import AppKit
import SwiftUI

/// PROTOTYPE menu bar — draft outbound only. Not the shipping companion.
struct PrototypeDraftMenuBar: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MailGent")
                .font(.headline)
            Text("PROTOTYPE · draft outbound")
                .font(.caption)
                .foregroundStyle(.orange)
            Text("A copy-paste vs B draft ledger. Pick a winner on ticket 06.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            Button("Open draft prototype") {
                openWindow(id: "draft-prototype")
            }
            .keyboardShortcut(.defaultAction)
            Button("Quit MailGent") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(16)
        .frame(width: 280)
    }
}
