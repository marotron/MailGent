import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class MailAccessSession {
    var snapshot = MailLibraryAccessSnapshot(
        canListMailDirectory: false,
        hasReadableFolderBookmark: false
    )

    func refresh() {
        let bookmark = MailFolderBookmark.resolvedURL()
        snapshot = MailLibraryAccessSnapshot(
            canListMailDirectory: MailLibraryProbe.canList(MailLibraryProbe.defaultMailDirectory),
            hasReadableFolderBookmark: bookmark.map(MailLibraryProbe.canList) ?? false
        )
    }

    func chooseMailFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Select Apple Mail’s data folder (usually ~/Library/Mail)."
        panel.directoryURL = MailLibraryProbe.defaultMailDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? MailFolderBookmark.save(url)
        refresh()
    }

    func openFullDiskAccessSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

struct GrantAccessView: View {
    @Bindable var session: MailAccessSession

    var body: some View {
        Form {
            Section(session.snapshot.headline) {
                Text(session.snapshot.explanation)
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Text("Companion will not write Apple Mail’s store.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                Button("Open Full Disk Access") {
                    session.openFullDiskAccessSettings()
                }
                .keyboardShortcut(.defaultAction)
                Button("Choose Mail Folder…") {
                    session.chooseMailFolder()
                }
                Button("Recheck") {
                    session.refresh()
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
