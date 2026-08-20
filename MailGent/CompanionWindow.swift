import AppKit
import MailStore
import SwiftUI

/// Menu-bar (`LSUIElement`) apps stay `.accessory`. SwiftUI `Window` / `Settings` /
/// `openWindow` / `SettingsLink` then fail after the first close. Own the windows in
/// AppKit: hide on close, flip to `.regular` on the click that shows them.
@MainActor
final class DetachedWindowHost: NSObject, NSWindowDelegate {
    static let shared = DetachedWindowHost()

    private var companion: NSWindow?
    private var access: NSWindow?

    func showCompanion(session: CompanionSession) {
        if companion == nil {
            companion = makeWindow(
                title: "MailGent",
                size: NSSize(width: 980, height: 640),
                minSize: NSSize(width: 720, height: 480),
                root: CompanionWindow(session: session)
            )
        }
        bringForward(companion)
    }

    func showAccess(session: MailAccessSession) {
        if access == nil {
            access = makeWindow(
                title: "Grant access",
                size: NSSize(width: 480, height: 280),
                minSize: NSSize(width: 420, height: 240),
                root: GrantAccessView(session: session)
            )
        }
        bringForward(access)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if companion?.isVisible != true, access?.isVisible != true {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        minSize: NSSize,
        root: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: root)
        window.minSize = minSize
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.center()
        return window
    }

    private func bringForward(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct CompanionWindow: View {
    @Bindable var session: CompanionSession

    var body: some View {
        Group {
            switch session.page {
            case .home:
                controlCenter
            case .search:
                CompanionSearchPage(session: session)
            case .read:
                CompanionReadPage(session: session)
            }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var controlCenter: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Control center")
                        .font(.title.bold())
                    Text("Access and ingest first. Mail search is a separate step.")
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 16) {
                    healthCard
                    ingestCard
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Detected on disk")
                        .font(.headline)
                    Text("Accounts and mailboxes in the Mail store. Counts are indexed messages. Tap a mailbox to search it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if session.scanCatalog.isEmpty {
                        Text(session.isIndexing ? "Scanning…" : "No accounts detected")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.scanCatalog) { account in
                            DetectedAccountCard(session: session, account: account)
                        }
                    }
                }

                Button("Search mail") {
                    session.openSearch(placement: nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var healthCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Access health")
                .font(.headline)
            Text(session.mailAccessGranted ? "Full Disk Access granted" : "Grant access to Mail")
                .foregroundStyle(session.mailAccessGranted ? .green : .orange)
            Text("Companion will not write Apple Mail’s store.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !session.mailAccessGranted {
                Button("Open grant settings…") {
                    session.access.openFullDiskAccessSettings()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.separator)
        }
    }

    private var ingestCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Last ingest")
                .font(.headline)
            if session.isIndexing {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(session.status)
                        .foregroundStyle(.secondary)
                }
                if session.indexedCount > 0 {
                    Text("\(session.indexedCount) indexed so far")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(session.lastIngestAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                Text("\(session.indexedCount) indexed · \(session.source.title)")
                    .foregroundStyle(.secondary)
                Text("\(session.scanAccounts) accounts · \(session.scanMailboxes) mailboxes · \(session.scanMessagesLabel) indexed")
                    .foregroundStyle(.secondary)
                Text(session.ingestPassNote == "Full reindex"
                    ? "Indexed \(session.indexedCount) from disk"
                    : (session.lastNewCount == 0 ? "No new this pass" : "\(session.lastNewCount) new this pass"))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Reindex now", action: session.reindexNow)
                    .disabled(session.isIndexing)
                if session.mailAccessGranted {
                    Button(session.source == .liveMail ? "Use fixture" : "Use live Mail") {
                        session.setSource(session.source == .liveMail ? .fixture : .liveMail)
                    }
                    .disabled(session.isIndexing)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.separator)
        }
    }
}

private struct DetectedAccountCard: View {
    let session: CompanionSession
    let account: DetectedAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName ?? CompanionAccounts.label(account.id))
                        .font(.subheadline.weight(.semibold))
                    if let email = account.email, !email.isEmpty, email != account.displayName {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else if let email = account.email,
                              let brand = MailAccountIdentityResolver.displayName(fromEmail: email),
                              brand != account.displayName
                    {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(account.id)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                Spacer()
                Text(account.hasPendingCounts ? "… indexed" : "\(account.messageCount) indexed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if account.mailboxes.isEmpty {
                Text("No mailboxes detected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(account.mailboxes) { mailbox in
                    Button {
                        session.openSearch(
                            placement: Placement(accountID: account.id, id: mailbox.placement)
                        )
                    } label: {
                        HStack {
                            Text(mailbox.placement)
                                .font(.caption)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(mailbox.messageCount < 0 ? "…" : "\(mailbox.messageCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(mailbox.messageCount <= 0 ? .tertiary : .secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .padding(.leading, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(session.isIndexing || mailbox.messageCount < 0)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).stroke(.separator)
        }
    }
}

private struct CompanionSearchPage: View {
    @Bindable var session: CompanionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button("Control center") {
                    session.openHome()
                }
                Text("Search mail")
                    .font(.title2.bold())
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            HStack {
                TextField("Find across accounts", text: $session.query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(session.refresh)
                Button("Search", action: session.refresh)
                PlacementMenu(session: session)
            }
            .padding(16)
            Text(session.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            Divider()
            if session.items.isEmpty {
                ContentUnavailableView(
                    "No messages",
                    systemImage: "envelope",
                    description: Text(session.status.isEmpty ? "Ingest fixture mail from the control center, then search." : session.status)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(session.items, id: \.rowID) { message in
                            Button {
                                session.openRead(message)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(message.subject.isEmpty ? "(no subject)" : message.subject)
                                            .font(.headline)
                                        if message.isPartial { PartialBadge() }
                                    }
                                    Text(message.from)
                                        .foregroundStyle(.secondary)
                                    SourceChip(session: session, accountID: message.accountID, placement: message.placement)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
            }
        }
        .onChange(of: session.query) { _, _ in
            if session.query.isEmpty { session.refresh() }
        }
    }
}

private struct CompanionReadPage: View {
    @Bindable var session: CompanionSession

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button("Search mail") {
                    session.page = .search
                }
                if let detail = session.detail {
                    Text(detail.subject.isEmpty ? "(no subject)" : detail.subject)
                        .font(.title2.bold())
                    SourceChip(session: session, accountID: detail.accountID, placement: detail.placement)
                    if detail.isPartial { PartialBadge() }
                    Text("From \(detail.from)")
                    Text("To \(detail.to)")
                        .foregroundStyle(.secondary)
                    Text(detail.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Divider()
                    MessageBodyView(readBody: detail.body)
                    OpenInMailButton(session: session)
                } else {
                    Text("Message not available")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(24)
        }
    }
}
