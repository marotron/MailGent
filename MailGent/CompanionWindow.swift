import AppKit
import MailStore
import SwiftUI

/// Menu-bar (`LSUIElement`) apps stay `.accessory`. SwiftUI `Window` / `Settings` /
/// `openWindow` / `SettingsLink` then fail after the first close. Own the windows in
/// AppKit: hide on close, flip to `.regular` on the click that shows them.
///
/// MenuBarExtra `.window` dismiss also calls `NSApp.hide()` / `orderOut` on the new
/// key window ~0.3–0.8s later. Delaying present is not enough — block those hides.
@MainActor
final class DetachedWindowHost: NSObject, NSWindowDelegate {
    static let shared = DetachedWindowHost()

    private var companion: NSWindow?
    private var access: NSWindow?
    private var grantDesk: NSWindow?
    private var accessLog: NSWindow?
    private var settings: NSWindow?
    /// Bumps when a new menu action schedules a present; stale delayed work bails.
    private var presentationToken = 0
    /// Only `windowShouldClose` (user close) may order out hosted windows.
    private var allowingOrderOut = false
    private var presentedAt: Date?
    private var hideRecoveries = 0
    private var hideObserver: NSObjectProtocol?
    /// Windows the user asked to keep; extra dismiss must not resurrect closed ones.
    private var intendedVisible: Set<ObjectIdentifier> = []

    /// AppKit may call `orderOut` off the isolated host; HostedWindow reads this on main.
    var shouldBlockOrderOut: Bool { !allowingOrderOut }

    /// MenuBarExtra dismiss calls `NSApp.hide()` after the click; swallow that while we own windows.
    var shouldSuppressAppHide: Bool { isRecentPresent || !intendedVisible.isEmpty }

    override init() {
        super.init()
        hideObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recoverFromHideIfNeeded()
            }
        }
    }

    func showCompanion(session: CompanionSession) {
        beginPresentation()
        scheduleAfterMenuDismissal {
            self.presentCompanion(session: session)
        }
    }

    func showAccess(session: MailAccessSession) {
        beginPresentation()
        scheduleAfterMenuDismissal {
            self.presentAccess(session: session)
        }
    }

    func showGrantDesk(session: CompanionSession) {
        beginPresentation()
        scheduleAfterMenuDismissal {
            self.presentGrantDesk(session: session)
        }
    }

    func showAccessLog(session: CompanionSession, selectedID: String? = nil) {
        beginPresentation()
        scheduleAfterMenuDismissal {
            self.presentAccessLog(session: session, selectedID: selectedID)
        }
    }

    func showSettings(session: CompanionSession) {
        beginPresentation()
        scheduleAfterMenuDismissal {
            self.presentSettings(session: session)
        }
    }

    /// Flip off `.accessory` on the click itself so MenuBarExtra dismiss does not hide the app.
    func claimActivation() {
        presentedAt = Date()
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func beginPresentation() {
        hideRecoveries = 0
        claimActivation()
    }

    private var isRecentPresent: Bool {
        guard let presentedAt else { return false }
        return Date().timeIntervalSince(presentedAt) < 1.2
    }

    private func wantsVisible(_ window: NSWindow) -> Bool {
        intendedVisible.contains(ObjectIdentifier(window))
    }

    private var hostedWindows: [NSWindow] {
        [companion, access, grantDesk, accessLog, settings].compactMap { $0 }
    }

    /// MenuBarExtra `.window` tears down on the same turn as the click; wait one turn.
    private func scheduleAfterMenuDismissal(_ body: @escaping () -> Void) {
        presentationToken += 1
        let token = presentationToken
        DispatchQueue.main.async { [weak self] in
            guard let self, token == self.presentationToken else { return }
            body()
        }
    }

    private func presentCompanion(session: CompanionSession) {
        let root = CompanionWindow(session: session)
        if let companion {
            install(root, in: companion)
        } else {
            companion = makeWindow(
                title: "MailGent",
                size: NSSize(width: 980, height: 640),
                minSize: NSSize(width: 720, height: 480),
                root: root
            )
        }
        bringForward(companion)
    }

    private func presentAccess(session: MailAccessSession) {
        let root = GrantAccessView(session: session)
        if let access {
            install(root, in: access)
        } else {
            access = makeWindow(
                title: "Grant access",
                size: NSSize(width: 440, height: 400),
                minSize: NSSize(width: 420, height: 300),
                root: root
            )
        }
        bringForward(access)
    }

    private func presentGrantDesk(session: CompanionSession) {
        let size = NSSize(width: 600, height: 640)
        let minSize = NSSize(width: 560, height: 520)
        let root = GrantDeskView(session: session)
        if let grantDesk {
            grantDesk.minSize = minSize
            install(root, in: grantDesk)
        } else {
            grantDesk = makeWindow(
                title: "Grant desk",
                size: size,
                minSize: minSize,
                root: root
            )
        }
        bringForward(grantDesk)
    }

    private func presentAccessLog(session: CompanionSession, selectedID: String?) {
        let size = NSSize(width: 900, height: 560)
        let minSize = NSSize(width: 780, height: 420)
        let root = AccessLogView(session: session, initialSelection: selectedID)
        if let accessLog {
            install(root, in: accessLog)
        } else {
            accessLog = makeWindow(
                title: "Access log",
                size: size,
                minSize: minSize,
                root: root
            )
        }
        bringForward(accessLog)
    }

    private func presentSettings(session: CompanionSession) {
        let size = NSSize(width: 480, height: 600)
        let minSize = NSSize(width: 440, height: 400)
        let root = MailGentSettingsView(session: session)
        if let settings {
            settings.minSize = minSize
            install(root, in: settings)
        } else {
            settings = makeWindow(
                title: "MailGent Settings",
                size: size,
                minSize: minSize,
                root: root
            )
        }
        bringForward(settings)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Extra dismiss synthesizes close on the new key window. Ignore that flash.
        if isRecentPresent { return false }
        intendedVisible.remove(ObjectIdentifier(sender))
        allowingOrderOut = true
        sender.orderOut(nil)
        allowingOrderOut = false
        if intendedVisible.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
        return false
    }

    private func recoverFromHideIfNeeded() {
        guard !intendedVisible.isEmpty else { return }
        guard hideRecoveries < 8 else { return }
        hideRecoveries += 1
        claimActivation()
        for window in hostedWindows where wantsVisible(window) {
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func makeWindow<Content: View>(
        title: String,
        size: NSSize,
        minSize: NSSize,
        root: Content
    ) -> NSWindow {
        let window = HostedWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = minSize
        window.setContentSize(size)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.canHide = false
        window.animationBehavior = .none
        window.delegate = self
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        install(root, in: window, contentSize: size)
        window.center()
        return window
    }

    private func install<Content: View>(_ root: Content, in window: NSWindow, contentSize: NSSize? = nil) {
        let size = contentSize ?? window.contentRect(forFrameRect: window.frame).size
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
    }

    private func bringForward(_ window: NSWindow?) {
        guard let window else { return }
        intendedVisible.insert(ObjectIdentifier(window))
        let token = presentationToken
        let poke = { [weak self] in
            guard let self, token == self.presentationToken else { return }
            self.claimActivation()
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
        poke()
        // Extra dismiss / NSApp.hide can still land after the first present.
        DispatchQueue.main.async { poke() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { poke() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { poke() }
    }
}

@objc(MailGentApplication)
final class MailGentApplication: NSApplication {
    override func hide(_ sender: Any?) {
        let suppress = MainActor.assumeIsolated {
            DetachedWindowHost.shared.shouldSuppressAppHide
        }
        if suppress { return }
        super.hide(sender)
    }
}

/// Status-item teardown calls `orderOut` on whoever became key. Only user close may hide us.
private final class HostedWindow: NSWindow {
    override func orderOut(_ sender: Any?) {
        let blocked = MainActor.assumeIsolated {
            DetachedWindowHost.shared.shouldBlockOrderOut
        }
        if blocked { return }
        super.orderOut(sender)
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
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Control center")
                            .font(.title.bold())
                        Text("Access and ingest first. Mail search is a separate step.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        Button("Grant desk…") {
                            DetachedWindowHost.shared.showGrantDesk(session: session)
                        }
                        Button("Access log…") {
                            DetachedWindowHost.shared.showAccessLog(session: session)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 16) {
                    healthCard
                    ingestCard
                }

                agentCard

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

    private var agentCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Paired agent")
                    .font(.headline)
                Spacer()
                if let agent = session.agents.agent {
                    Text("\(agent.name) · \(agent.trustClass.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No agent paired")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if session.agents.agent != nil {
                Text(session.agents.listenNote)
                    .font(.caption)
                    .foregroundStyle(session.agents.isListening ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                Text(session.agents.cursorConfigSnippet)
                    .font(.system(.caption2, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(spacing: 8) {
                if session.agents.agent != nil {
                    Button("Revoke credential") {
                        session.agents.revoke()
                        session.agents.ensureMachineLocalAgent()
                    }
                } else {
                    Button("Pair Cursor") {
                        session.agents.ensureMachineLocalAgent()
                    }
                }
            }
            if session.agents.agent != nil {
                Text(session.agents.currentGrants.isEmpty
                     ? "Nothing granted — agent search stays empty."
                     : "\(session.agents.currentGrants.count) grant(s) active · edit in grant desk")
                    .font(.caption)
                    .foregroundStyle(session.agents.currentGrants.isEmpty ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.secondary))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.separator)
        }
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
            Divider()
            CompanionStatusMetrics(session: session)
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
                ingestProgressBlock
                if session.indexedCount > 0 {
                    Text("\(session.indexedCount) indexed so far")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(session.lastIngestAt?.formatted(date: .abbreviated, time: .shortened) ?? "Never")
                Text("\(session.indexedCount) indexed · \(session.source.title)")
                    .foregroundStyle(session.source == .fixture ? Color.purple : Color.secondary)
                    .fontWeight(session.source == .fixture ? .semibold : .regular)
                Text("\(session.scanAccounts) accounts · \(session.scanMailboxes) mailboxes · \(session.scanMessagesLabel) indexed")
                    .foregroundStyle(.secondary)
                Text(ingestSummary)
                    .foregroundStyle(.secondary)
                if session.isUpdating {
                    ingestProgressBlock
                }
            }
            HStack {
                Button("Update", action: session.ingestAgain)
                    .disabled(session.isBusy)
                Button("Reindex now", action: session.reindexNow)
                    .disabled(session.isBusy)
                Button("Next source") {
                    session.cycleSource()
                }
                .disabled(session.isBusy || !session.canCycleSource)
                .help("Switch to \(session.nextSource.title)")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).stroke(.separator)
        }
    }

    private var ingestSummary: String {
        switch session.ingestPassNote {
        case "Full reindex":
            return "Indexed \(session.indexedCount) from disk"
        case "Loaded from disk":
            return "Opened existing index"
        default:
            return session.lastNewCount == 0 ? "No new this pass" : "\(session.lastNewCount) new this pass"
        }
    }

    @ViewBuilder
    private var ingestProgressBlock: some View {
        if let total = session.ingestTotal, total > 0 {
            ProgressView(value: Double(min(session.ingestProcessed, total)), total: Double(total))
            Text(session.ingestCurrentTask.isEmpty ? session.status : session.ingestCurrentTask)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(session.ingestCurrentTask.isEmpty ? session.status : session.ingestCurrentTask)
                    .foregroundStyle(.secondary)
            }
        }
        if session.ingestProcessed > 0 || session.ingestInserted > 0 {
            Text("\(session.ingestInserted) new / \(session.ingestProcessed) scanned")
                .foregroundStyle(.secondary)
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
                Button {
                    session.openHome()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Control center")
                    }
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
    @State private var showRaw = false

    var body: some View {
        Group {
            if let detail = session.detail {
                let htmlScroll = usesHTMLScroll(for: detail)
                VStack(alignment: .leading, spacing: 0) {
                    readHeader(detail: detail)
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 12)

                    Divider()

                    if htmlScroll {
                        MessageBodyView(
                            readBody: detail.body,
                            htmlBody: detail.htmlBody,
                            rawBody: detail.rawBody,
                            showRaw: showRaw
                        )
                        .id(detail.rowID)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        OpenInMailButton(session: session)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                MessageBodyView(
                                    readBody: detail.body,
                                    htmlBody: detail.htmlBody,
                                    rawBody: detail.rawBody,
                                    showRaw: showRaw
                                )
                                .id(detail.rowID)
                                OpenInMailButton(session: session)
                            }
                            .padding(24)
                        }
                    }
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        backButton
                        Text("Message not available")
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                }
            }
        }
        .onChange(of: session.detail?.rowID) { _, _ in
            showRaw = false
        }
    }

    private func usesHTMLScroll(for detail: ReadMessage) -> Bool {
        let showingRaw = showRaw
            && !detail.rawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !showingRaw else { return false }
        return !(detail.htmlBody ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var backButton: some View {
        Button {
            session.page = .search
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left")
                Text("Search mail")
            }
        }
    }

    @ViewBuilder
    private func readHeader(detail: ReadMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            backButton
            Text(detail.subject.isEmpty ? "(no subject)" : detail.subject)
                .font(.title2.bold())
            AddressLine(label: "From", raw: detail.from)
            AddressLine(label: "To", raw: detail.to) {
                Text(detail.placement)
                    .foregroundStyle(.secondary)
                if detail.isPartial { PartialBadge() }
            }
            HStack(alignment: .center) {
                Text(detail.date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if !detail.rawBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    BodyFormatPicker(showRaw: $showRaw)
                }
            }
        }
    }
}
