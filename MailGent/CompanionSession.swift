import AppKit
import Foundation
import MailStore
import Observation

enum CompanionPage: Equatable {
    case home
    case search
    case read
}

extension MailSourceID {
    var title: String {
        switch self {
        case .fixture: "Fixture mail"
        case .liveMail: "Live Mail store"
        }
    }
}

typealias CompanionMailSource = MailSourceID


struct DetectedMailbox: Equatable, Identifiable, Sendable {
    let accountID: String
    let placement: String
    let messageCount: Int

    var id: String { "\(accountID)/\(placement)" }
}

struct DetectedAccount: Equatable, Identifiable, Sendable {
    let id: String
    var displayName: String?
    var email: String?
    let mailboxes: [DetectedMailbox]

    var messageCount: Int {
        mailboxes.reduce(0) { partial, mailbox in
            partial + max(mailbox.messageCount, 0)
        }
    }

    var hasPendingCounts: Bool {
        mailboxes.contains { $0.messageCount < 0 }
    }
}

@MainActor
@Observable
final class CompanionSession {
    let access = MailAccessSession()
    var page: CompanionPage = .home
    var source: CompanionMailSource = .fixture
    var query = ""
    var selectedPlacement: Placement?
    var items: [IndexedMessage] = []
    var placements: [Placement] = []
    var detail: ReadMessage?
    var lastIngestAt: Date?
    /// Lower bound for the last incremental pass (previous `lastIngestAt` before that pass).
    var lastNewSinceAt: Date?
    var lastNewCount = 0
    var lastNewMessages: [IndexedMessage] = []
    var ingestPassNote = ""
    var indexedCount = 0
    var scanAccounts = 0
    var scanMailboxes = 0
    var scanMessages = 0
    var scanCatalog: [DetectedAccount] = []
    var status = ""
    var handoffNote: String?
    var mailAccessGranted: Bool { access.snapshot.access == .granted }
    var isIndexing = false
    var isUpdating = false
    var ingestProcessed = 0
    var ingestTotal: Int?
    var ingestInserted = 0
    var ingestCurrentTask = ""
    let agents = AgentBridge()

    var isBusy: Bool { isIndexing || isUpdating }

    var scanMessagesLabel: String {
        if scanCatalog.contains(where: \.hasPendingCounts) {
            return "…"
        }
        return String(scanMessages)
    }

    func accountLabel(_ accountID: String) -> String {
        if let account = scanCatalog.first(where: { $0.id == accountID }),
           let displayName = account.displayName,
           !displayName.isEmpty
        {
            return displayName
        }
        return CompanionAccounts.label(accountID)
    }

    private var fixtureRoot: URL
    private var fixtureDatabaseURL: URL
    private let liveDatabaseURL: URL
    private var arrivalWave = 0
    private let worker = MailIndexWorker()
    private var indexTask: Task<Void, Never>?

    private var databaseURL: URL {
        switch source {
        case .fixture: fixtureDatabaseURL
        case .liveMail: liveDatabaseURL
        }
    }

    init() {
        let stamp = UUID().uuidString
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(stamp)", isDirectory: true)
        fixtureDatabaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(stamp).sqlite")
        liveDatabaseURL = Self.liveMailDatabaseURL()
        refreshAccess()
        agents.ensureMachineLocalAgent()
        scheduleReload(reason: "startup")
    }

    func refreshAccess() {
        access.refresh()
    }

    var availableSources: [MailSourceID] {
        MailSourceID.available(liveMailAccessible: mailAccessGranted)
    }

    var nextSource: MailSourceID {
        source.next(in: availableSources)
    }

    var canCycleSource: Bool {
        nextSource != source
    }

    func cycleSource() {
        guard !isBusy, canCycleSource else { return }
        setSource(nextSource)
    }

    func setSource(_ source: CompanionMailSource) {
        guard self.source != source else { return }
        self.source = source
        selectedPlacement = nil
        detail = nil
        query = ""
        scheduleReload(reason: "source-\(source.rawValue)")
    }

    func applyAgentSource(_ source: MailSourceID) throws -> MailSourceSnapshot {
        guard MailGentPreferences.agentMayChangeSource else {
            throw MailSourceError.denied
        }
        guard availableSources.contains(source) else {
            throw MailSourceError.unavailable
        }
        setSource(source)
        return sourceSnapshot()
    }

    func sourceSnapshot() -> MailSourceSnapshot {
        MailSourceSnapshot(
            source: source,
            agentMayChangeSource: MailGentPreferences.agentMayChangeSource
        )
    }

    func reindexNow() {
        scheduleReload(reason: "reindex")
    }

    func ingestAgain() {
        guard !isBusy else { return }
        indexTask?.cancel()
        indexTask = Task {
            await performIncrementalIngest()
        }
    }

    func refresh() {
        guard !isIndexing else { return }
        Task {
            await refreshFromWorker()
        }
    }

    func select(_ message: IndexedMessage) {
        Task {
            do {
                detail = try await worker.readMessage(
                    accountID: message.accountID,
                    placement: message.placement,
                    id: message.id
                )
                handoffNote = nil
            } catch {
                detail = nil
                status = "Message not available"
            }
        }
    }

    func openInMail() {
        handoffNote = "Apple Mail handoff needs a Message-ID this index does not store yet."
    }

    func openAttachment(_ attachment: MailAttachment, of message: ReadMessage) {
        Task {
            do {
                let data = try await worker.attachmentData(
                    accountID: message.accountID,
                    placement: message.placement,
                    id: message.id,
                    filename: attachment.filename
                )
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MailGent-attachments", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let safeName = URL(fileURLWithPath: attachment.filename).lastPathComponent
                let file = directory.appendingPathComponent(safeName)
                try data.write(to: file, options: .atomic)
                NSWorkspace.shared.open(file)
            } catch {
                status = "Could not open \(attachment.filename)"
            }
        }
    }

    func openHome() {
        page = .home
        query = ""
        selectedPlacement = nil
        detail = nil
        refresh()
    }

    func openSearch(placement: Placement?) {
        selectedPlacement = placement
        if placement != nil { query = "" }
        page = .search
        refresh()
    }

    /// Opens companion search on messages from the last incremental ingest pass.
    func openLastNewMessages() {
        selectedPlacement = nil
        detail = nil
        page = .search
        if !query.isEmpty {
            query = ""
        }
        let news = lastNewMessages
        items = news
        status = news.isEmpty ? "No new messages" : "\(news.count) new this pass"
        // Search page clears query → onChange may refresh and overwrite; re-pin after.
        Task { @MainActor in
            self.items = self.lastNewMessages
            self.status = self.lastNewMessages.isEmpty
                ? "No new messages"
                : "\(self.lastNewMessages.count) new this pass"
        }
    }

    func openRead(_ message: IndexedMessage) {
        select(message)
        page = .read
    }

    /// Opens Companion Read from an audit message ref (re-fetches body; no body in audit).
    func openRead(accountID: String, placement: String, id: String) {
        page = .read
        Task {
            do {
                detail = try await worker.readMessage(
                    accountID: accountID,
                    placement: placement,
                    id: id
                )
                handoffNote = nil
            } catch {
                detail = nil
                status = "Message not available"
            }
        }
    }

    private func scheduleReload(reason: String) {
        indexTask?.cancel()
        indexTask = Task {
            await performReload(reason: reason)
        }
    }

    private enum StorePrepResult: Sendable {
        case ready(MailStore)
        case denied(message: String, fallback: CompanionMailSource)
        case failed(message: String)
    }

    private func performReload(reason: String) async {
        isIndexing = true
        isUpdating = false
        resetIngestProgress()
        clearDetectedCatalog()
        placements = []
        items = []
        indexedCount = 0
        status = "Scanning Mail store…"
        MailGentLog.trace("reload scheduled reason=\(reason) source=\(source.rawValue)")

        let source = self.source
        let mailAccessGranted = self.mailAccessGranted
        let fixtureRoot = self.fixtureRoot
        let databaseURL = self.databaseURL
        let wipe = reason == "reindex" || source == .fixture

        let prepResult: StorePrepResult
        do {
            prepResult = try await Task.detached(priority: .userInitiated) {
                try Task.checkCancellation()
                switch source {
                case .fixture:
                    try? FileManager.default.removeItem(at: fixtureRoot)
                    try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
                    let mail = fixtureRoot.appendingPathComponent("Mail", isDirectory: true)
                    try CompanionFixture.plant(at: mail)
                    return .ready(MailStore(root: mail))
                case .liveMail:
                    guard mailAccessGranted else {
                        return .denied(message: "Grant access to Mail first", fallback: .fixture)
                    }
                    guard let root = MailLibraryProbe.resolvedMailRoot() else {
                        return .failed(message: "Mail folder is not readable")
                    }
                    MailGentLog.trace("live mail root=\(root.path)")
                    return .ready(MailStore(root: root))
                }
            }.value
        } catch is CancellationError {
            MailGentLog.trace("reload cancelled during store prep reason=\(reason)")
            isIndexing = false
            return
        } catch {
            MailGentLog.trace("reload store prep failed: \(error)")
            clearIndexState(status: "Index failed (\(error))")
            isIndexing = false
            return
        }

        guard !Task.isCancelled else {
            isIndexing = false
            return
        }

        let store: MailStore
        switch prepResult {
        case let .ready(preparedStore):
            store = preparedStore
        case let .denied(message, fallback):
            self.source = fallback
            clearIndexState(status: message)
            isIndexing = false
            return
        case let .failed(message):
            clearIndexState(status: message)
            isIndexing = false
            return
        }

        if source == .fixture {
            arrivalWave = 0
        }

        await worker.reset()

        do {
            let structure = try await worker.scanStructure(store: store)
            applyCatalog(structure)
            status = "Listing \(structure.accountsCount) accounts…"
            MailGentLog.trace("structure ready accounts=\(structure.accountsCount) mailboxes=\(structure.mailboxesCount)")

            if !wipe,
               source == .liveMail,
               FileManager.default.fileExists(atPath: databaseURL.path),
               try await openExistingIndex(store: store, databaseURL: databaseURL)
            {
                isIndexing = false
                await performIncrementalIngest()
                return
            }

            let snapshot = try await worker.rebuild(store: store, databaseURL: databaseURL) { [weak self] progress in
                Task { @MainActor in
                    self?.applyIngestProgress(progress)
                }
            }
            guard !Task.isCancelled else {
                isIndexing = false
                return
            }
            applyCatalog(snapshot.catalog)
            indexedCount = snapshot.indexedCount
            placements = snapshot.placements
            lastIngestAt = snapshot.lastIngestAt
            lastNewSinceAt = nil
            lastNewCount = 0
            lastNewMessages = []
            ingestPassNote = "Full reindex"
            items = []
            detail = nil
            bindLoopbackWithUpdater(store: store, databaseURL: databaseURL)
            await refreshFromWorker()
            MailGentLog.trace(
                "reload finished indexed=\(snapshot.indexedCount) onDisk=\(snapshot.catalog.messagesCount)"
            )
        } catch is CancellationError {
            MailGentLog.trace("reload cancelled during ingest reason=\(reason)")
            status = "Index cancelled"
        } catch {
            MailGentLog.trace("reload ingest failed: \(error)")
            clearIndexState(status: "Index failed (\(error))")
        }

        isIndexing = false
    }

    private func openExistingIndex(store: MailStore, databaseURL: URL) async throws -> Bool {
        do {
            let opened = try await worker.open(store: store, databaseURL: databaseURL)
            guard opened.indexedCount > 0 else { return false }
            applyCatalog(opened.catalog)
            indexedCount = opened.indexedCount
            placements = opened.placements
            lastIngestAt = opened.lastIngestAt
            lastNewSinceAt = nil
            lastNewCount = 0
            lastNewMessages = []
            ingestPassNote = "Loaded from disk"
            items = []
            detail = nil
            bindLoopbackWithUpdater(store: store, databaseURL: databaseURL)
            await refreshFromWorker()
            MailGentLog.trace("opened existing index indexed=\(opened.indexedCount)")
            return true
        } catch {
            if error is CancellationError { throw error }
            MailGentLog.trace("open failed, rebuilding: \(error)")
            await worker.reset()
            return false
        }
    }

    private func performIncrementalIngest() async {
        isUpdating = true
        resetIngestProgress()
        status = "Checking for new messages…"
        ingestCurrentTask = "Checking for new messages…"
        MailGentLog.trace("incremental ingest scheduled source=\(source.rawValue)")

        if source == .fixture {
            let mail = fixtureRoot.appendingPathComponent("Mail", isDirectory: true)
            let wave = arrivalWave
            do {
                try await Task.detached(priority: .userInitiated) {
                    try CompanionFixture.plantArrival(at: mail, wave: wave)
                }.value
                arrivalWave += 1
            } catch {
                status = "Ingest failed"
                isUpdating = false
                return
            }
        }

        do {
            _ = try await runIncrementalIngestCore()
        } catch is CancellationError {
            status = "Ingest cancelled"
        } catch MailIndexWorkerError.notReady {
            status = "Index not ready"
        } catch {
            MailGentLog.trace("incremental ingest failed: \(error)")
            status = "Ingest failed"
        }

        isUpdating = false
    }

    /// Shared path for UI Update and MCP `update` (waits for completion).
    private func runIncrementalIngestCore() async throws -> IndexUpdateOutcome {
        let snapshot = try await worker.incrementalIngest { [weak self] progress in
            Task { @MainActor in
                self?.applyIngestProgress(progress)
            }
        }
        try Task.checkCancellation()
        applyCatalog(snapshot.catalog)
        indexedCount = snapshot.indexedCount
        placements = snapshot.placements
        lastNewSinceAt = lastIngestAt
        lastIngestAt = snapshot.lastIngestAt
        lastNewCount = snapshot.newCount
        lastNewMessages = snapshot.newMessages
        ingestPassNote = "Incremental"
        status = snapshot.newCount == 0 ? "No new messages" : "Ingested \(snapshot.newCount) new"
        await refreshFromWorker()
        return IndexUpdateOutcome(
            newCount: snapshot.newCount,
            freshness: IndexFreshness(
                lastIngestAt: snapshot.lastIngestAt,
                newestMessageDate: snapshot.newestMessageDate,
                indexedCount: snapshot.indexedCount
            )
        )
    }

    private func bindLoopbackWithUpdater(store: MailStore, databaseURL: URL) {
        let updater = BlockingIndexUpdater { [weak self] in
            guard let self else {
                throw MailIndexWorkerError.notReady
            }
            return try await self.updateIndexForMCP()
        }
        agents.bindLoopback(
            store: store,
            databaseURL: databaseURL,
            indexUpdater: updater,
            sourceController: makeSourceController()
        )
    }

    private func makeSourceController() -> BlockingMailSourceController {
        BlockingMailSourceController(
            snapshot: { [weak self] in
                await MainActor.run {
                    self?.sourceSnapshot()
                        ?? MailSourceSnapshot(source: .fixture, agentMayChangeSource: false)
                }
            },
            setSource: { [weak self] id in
                try await MainActor.run {
                    guard let self else { throw MailSourceError.notAvailable }
                    return try self.applyAgentSource(id)
                }
            }
        )
    }

    private func updateIndexForMCP() async throws -> IndexUpdateOutcome {
        guard !isBusy else {
            throw MailIndexWorkerError.notReady
        }
        isUpdating = true
        resetIngestProgress()
        status = "Checking for new messages…"
        ingestCurrentTask = "Checking for new messages…"
        defer { isUpdating = false }

        if source == .fixture {
            let mail = fixtureRoot.appendingPathComponent("Mail", isDirectory: true)
            let wave = arrivalWave
            try await Task.detached(priority: .userInitiated) {
                try CompanionFixture.plantArrival(at: mail, wave: wave)
            }.value
            arrivalWave += 1
        }

        return try await runIncrementalIngestCore()
    }

    private func refreshFromWorker() async {
        do {
            let snapshot = try await worker.page(
                query: query,
                selectedPlacement: selectedPlacement,
                currentDetail: detail
            )
            placements = snapshot.placements
            items = snapshot.items
            detail = snapshot.detail
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                indexedCount = snapshot.indexedCount
            } else if snapshot.indexedCount > 0 {
                indexedCount = snapshot.indexedCount
            }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            status = trimmed.isEmpty ? "\(items.count) messages" : "\(items.count) hits for \(trimmed)"
        } catch MailIndexWorkerError.notReady {
            items = []
            if !isIndexing {
                status = "Index not ready"
            }
        } catch {
            items = []
            status = "Search failed"
        }
    }

    private func applyCatalog(_ catalog: IndexCatalogSnapshot) {
        scanCatalog = catalog.accounts
        scanAccounts = catalog.accountsCount
        scanMailboxes = catalog.mailboxesCount
        scanMessages = max(catalog.messagesCount, 0)
        agents.ensureMachineLocalAgent()
    }

    private func applyIngestProgress(_ progress: IngestProgress) {
        ingestProcessed = progress.processed
        ingestTotal = progress.totalHint
        ingestInserted = progress.inserted
        let verb: String
        switch progress.phase {
        case .scanning:
            verb = "Scanning"
        case .indexing:
            verb = isUpdating ? "Checking" : "Indexing"
            if isIndexing {
                indexedCount = progress.inserted
            }
        }
        ingestCurrentTask = "\(verb) \(accountLabel(progress.accountID)) / \(progress.mailboxID)"
        status = ingestCurrentTask
    }

    private func resetIngestProgress() {
        ingestProcessed = 0
        ingestTotal = nil
        ingestInserted = 0
        ingestCurrentTask = ""
    }

    private func clearDetectedCatalog() {
        scanCatalog = []
        scanAccounts = 0
        scanMailboxes = 0
        scanMessages = 0
    }

    private func clearIndexState(status: String) {
        agents.stopLoopback()
        clearDetectedCatalog()
        indexedCount = 0
        placements = []
        items = []
        detail = nil
        lastNewCount = 0
        lastNewMessages = []
        lastIngestAt = nil
        lastNewSinceAt = nil
        self.status = status
    }

    private static func liveMailDatabaseURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailGent", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("live-mail.sqlite")
    }
}

extension IndexedMessage {
    var rowID: String { "\(accountID)/\(placement)/\(id)" }
}

extension ReadMessage {
    var rowID: String { "\(accountID)/\(placement)/\(id)" }
}

extension Placement {
    var rowID: String { "\(accountID)/\(id)" }
}
