import Foundation
import MailStore
import Observation

enum CompanionPage: Equatable {
    case home
    case search
    case read
}

enum CompanionMailSource: String, CaseIterable, Identifiable {
    case fixture
    case liveMail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixture: "Fixture mail"
        case .liveMail: "Live Mail store"
        }
    }
}

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
    var lastNewCount = 0
    var ingestPassNote = ""
    var indexedCount = 0
    var scanAccounts = 0
    var scanMailboxes = 0
    var scanMessages = 0
    var scanCatalog: [DetectedAccount] = []
    var status = ""
    var handoffNote: String?
    var mailAccessGranted = false
    var isIndexing = false

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
    private var databaseURL: URL
    private var arrivalWave = 0
    private let worker = MailIndexWorker()
    private var indexTask: Task<Void, Never>?

    init() {
        let stamp = UUID().uuidString
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(stamp)", isDirectory: true)
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(stamp).sqlite")
        refreshAccess()
        scheduleReload(reason: "startup")
    }

    func refreshAccess() {
        access.refresh()
        mailAccessGranted = access.snapshot.access == .granted
    }

    func setSource(_ source: CompanionMailSource) {
        guard self.source != source else { return }
        self.source = source
        selectedPlacement = nil
        detail = nil
        query = ""
        scheduleReload(reason: "source-\(source.rawValue)")
    }

    func reindexNow() {
        scheduleReload(reason: "reindex")
    }

    func ingestAgain() {
        guard !isIndexing else { return }
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

    func openRead(_ message: IndexedMessage) {
        select(message)
        page = .read
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

            let snapshot = try await worker.rebuild(store: store, databaseURL: databaseURL) { [weak self] line in
                Task { @MainActor in
                    guard let self else { return }
                    self.status = line
                    if line.hasPrefix("Indexing "), let indexed = Self.parseLeadingInt(after: "Indexing ", in: line) {
                        self.indexedCount = indexed
                    }
                }
            }
            guard !Task.isCancelled else {
                isIndexing = false
                return
            }
            applyCatalog(snapshot.catalog)
            indexedCount = snapshot.indexedCount
            placements = snapshot.placements
            lastIngestAt = Date()
            lastNewCount = 0
            ingestPassNote = "Full reindex"
            items = []
            detail = nil
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

    private func performIncrementalIngest() async {
        isIndexing = true
        status = "Checking for new messages…"
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
                isIndexing = false
                return
            }
        }

        do {
            let snapshot = try await worker.incrementalIngest { [weak self] line in
                Task { @MainActor in
                    self?.status = line
                }
            }
            guard !Task.isCancelled else {
                isIndexing = false
                return
            }
            applyCatalog(snapshot.catalog)
            indexedCount = snapshot.indexedCount
            placements = snapshot.placements
            lastIngestAt = Date()
            lastNewCount = snapshot.newCount
            ingestPassNote = "Incremental"
            status = snapshot.newCount == 0 ? "No new messages" : "Ingested \(snapshot.newCount) new"
            await refreshFromWorker()
        } catch is CancellationError {
            status = "Ingest cancelled"
        } catch MailIndexWorkerError.notReady {
            status = "Index not ready"
        } catch {
            MailGentLog.trace("incremental ingest failed: \(error)")
            status = "Ingest failed"
        }

        isIndexing = false
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
    }

    private func clearDetectedCatalog() {
        scanCatalog = []
        scanAccounts = 0
        scanMailboxes = 0
        scanMessages = 0
    }

    private func clearIndexState(status: String) {
        clearDetectedCatalog()
        indexedCount = 0
        placements = []
        items = []
        detail = nil
        lastNewCount = 0
        self.status = status
    }

    private static func parseLeadingInt(after prefix: String, in line: String) -> Int? {
        guard line.hasPrefix(prefix) else { return nil }
        let digits = line.dropFirst(prefix.count).prefix(while: \.isNumber)
        guard !digits.isEmpty else { return nil }
        return Int(digits)
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
