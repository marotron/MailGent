import AppKit
import Observation
import SwiftUI

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

struct RootView: View {
    @Bindable var session: MailAccessSession

    var body: some View {
        Group {
            switch session.snapshot.access {
            case .denied:
                GrantAccessView(session: session)
            case .granted:
                AccessGrantedPlaceholder()
            }
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear(perform: session.refresh)
    }
}

struct GrantAccessView: View {
    var session: MailAccessSession

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant access to Mail")
                .font(.title2)
                .bold()
            Text(
                "MailGent reads Apple Mail’s local store on this Mac. macOS Full Disk Access is a System Settings grant — no entitlement can skip it. Until that grant succeeds, MailGent will not read mail."
            )
            .foregroundStyle(.secondary)
            Text(
                "System Settings → Privacy & Security → Full Disk Access → enable MailGent. Then return here and Recheck. You can also choose the Mail folder as a fallback."
            )
            .foregroundStyle(.secondary)
            HStack {
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
        .padding(28)
    }
}

struct AccessGrantedPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mail access granted")
                .font(.title2)
                .bold()
            Text("Companion search and the Mail store reader land in later tickets. MailGent will not write Apple Mail’s store.")
                .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
