import Foundation
import MailStore

struct IndexCatalogSnapshot: Sendable {
    let accounts: [DetectedAccount]
    let accountsCount: Int
    let mailboxesCount: Int
    let messagesCount: Int
}

struct IndexRebuildSnapshot: Sendable {
    let catalog: IndexCatalogSnapshot
    let indexedCount: Int
    let placements: [Placement]
    let newCount: Int
    let lastIngestAt: Date?
}

struct IndexIncrementalSnapshot: Sendable {
    let catalog: IndexCatalogSnapshot
    let indexedCount: Int
    let placements: [Placement]
    let newCount: Int
    let newMessages: [IndexedMessage]
    let removedCount: Int
    let lastIngestAt: Date?
    let newestMessageDate: String?
}

struct IndexPageSnapshot: Sendable {
    let items: [IndexedMessage]
    let placements: [Placement]
    let indexedCount: Int
    let detail: ReadMessage?
}

/// Owns `MailboxIndex` / SQLite on one serial executor so ingest never blocks SwiftUI.
actor MailIndexWorker {
    private var index: MailboxIndex?
    private var api: ReadAPI?

    func rebuild(
        store: MailStore,
        databaseURL: URL,
        onProgress: (@Sendable (IngestProgress) -> Void)? = nil
    ) async throws -> IndexRebuildSnapshot {
        MailGentLog.trace("rebuild start root=\(store.root.path)")
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: databaseURL)

        let index = try MailboxIndex(store: store, databaseURL: databaseURL)
        let totalHint = try countMessages(store: store, onProgress: onProgress)

        try Task.checkCancellation()
        MailGentLog.trace("ingest begin totalHint=\(totalHint)")
        let ingest = try index.ingest(totalHint: totalHint) { progress in
            if progress.processed == 1 || progress.processed % 100 == 0 {
                MailGentLog.trace(
                    "ingest processed=\(progress.processed) indexed=\(progress.inserted) \(progress.accountID)/\(progress.mailboxID)"
                )
            }
            onProgress?(progress)
        }
        let api = ReadAPI(index: index)
        self.index = index
        self.api = api

        let indexedCount = try api.totalIndexed()
        let placements = try api.listPlacements()
        let catalog = try Self.catalogFromIndex(
            structure: nil,
            indexedCounts: try api.placementIndexedCounts(),
            store: store
        )
        MailGentLog.trace(
            "rebuild done indexed=\(indexedCount) new=\(ingest.new.count)"
        )
        let freshness = try index.freshness()
        return IndexRebuildSnapshot(
            catalog: catalog,
            indexedCount: indexedCount,
            placements: placements,
            newCount: ingest.new.count,
            lastIngestAt: freshness.lastIngestAt
        )
    }

    func open(store: MailStore, databaseURL: URL) async throws -> IndexRebuildSnapshot {
        MailGentLog.trace("open start db=\(databaseURL.path)")
        try Task.checkCancellation()
        let index = try MailboxIndex(store: store, databaseURL: databaseURL)
        let api = ReadAPI(index: index)
        self.index = index
        self.api = api

        let indexedCount = try api.totalIndexed()
        let placements = try api.listPlacements()
        let catalog = try Self.catalogFromIndex(
            structure: nil,
            indexedCounts: try api.placementIndexedCounts(),
            store: store
        )
        MailGentLog.trace("open done indexed=\(indexedCount)")
        let freshness = try index.freshness()
        return IndexRebuildSnapshot(
            catalog: catalog,
            indexedCount: indexedCount,
            placements: placements,
            newCount: 0,
            lastIngestAt: freshness.lastIngestAt
        )
    }

    func scanStructure(store: MailStore) async throws -> IndexCatalogSnapshot {
        try Self.scanCatalogStructure(store: store)
    }

    func incrementalIngest(onProgress: (@Sendable (IngestProgress) -> Void)? = nil) async throws -> IndexIncrementalSnapshot {
        guard let index, let api else {
            throw MailIndexWorkerError.notReady
        }
        MailGentLog.trace("incremental ingest start")
        let ingest = try index.ingest { progress in
            onProgress?(progress)
        }
        let indexedCount = try api.totalIndexed()
        let placements = try api.listPlacements()
        let catalog = try Self.catalogFromIndex(
            structure: nil,
            indexedCounts: try api.placementIndexedCounts(),
            store: index.store
        )
        MailGentLog.trace("incremental ingest done new=\(ingest.new.count) removed=\(ingest.removed.count) indexed=\(indexedCount)")
        let freshness = try index.freshness()
        let newMessages: [IndexedMessage] = ingest.new.compactMap { ref in
            try? index.get(accountID: ref.accountID, placement: ref.placement, id: ref.id)
        }
        return IndexIncrementalSnapshot(
            catalog: catalog,
            indexedCount: indexedCount,
            placements: placements,
            newCount: ingest.new.count,
            newMessages: newMessages,
            removedCount: ingest.removed.count,
            lastIngestAt: freshness.lastIngestAt,
            newestMessageDate: freshness.newestMessageDate
        )
    }

    func page(
        query: String,
        selectedPlacement: Placement?,
        currentDetail: ReadMessage?
    ) async throws -> IndexPageSnapshot {
        guard let api else {
            throw MailIndexWorkerError.notReady
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountID = selectedPlacement?.accountID
        let placementID = selectedPlacement?.id
        let page = trimmed.isEmpty
            ? try api.list(limit: 100, accountID: accountID, placement: placementID)
            : try api.search(trimmed, limit: 100, accountID: accountID, placement: placementID)
        let placements = try api.listPlacements()
        let indexedCount = trimmed.isEmpty ? try api.totalIndexed() : 0
        let filtered = page.items
        var detail = currentDetail
        if let detailValue = detail, !filtered.contains(where: { $0.rowID == detailValue.rowID }) {
            detail = nil
        }
        return IndexPageSnapshot(
            items: filtered,
            placements: placements,
            indexedCount: indexedCount,
            detail: detail
        )
    }

    func readMessage(accountID: String, placement: String, id: String) async throws -> ReadMessage {
        guard let api else {
            throw MailIndexWorkerError.notReady
        }
        return try api.get(accountID: accountID, placement: placement, id: id)
    }

    func attachmentData(
        accountID: String,
        placement: String,
        id: String,
        filename: String
    ) async throws -> Data {
        guard let index else {
            throw MailIndexWorkerError.notReady
        }
        return try index.store.attachmentData(
            accountID: accountID,
            mailbox: placement,
            messageID: id,
            filename: filename
        )
    }

    func reset() {
        index = nil
        api = nil
    }

    private func countMessages(
        store: MailStore,
        onProgress: (@Sendable (IngestProgress) -> Void)?
    ) throws -> Int {
        var total = 0
        for account in try store.accounts() {
            try Task.checkCancellation()
            for mailbox in try store.mailboxes(in: account.id) {
                try Task.checkCancellation()
                onProgress?(
                    IngestProgress(
                        processed: total,
                        inserted: 0,
                        accountID: account.id,
                        mailboxID: mailbox.id,
                        phase: .scanning,
                        totalHint: nil
                    )
                )
                total += try store.messageCount(in: account.id, mailbox: mailbox.id)
            }
        }
        return total
    }

    nonisolated static func scanCatalogStructure(store: MailStore) throws -> IndexCatalogSnapshot {
        var accounts: [DetectedAccount] = []
        var mailboxTotal = 0

        for account in try store.accounts() {
            try Task.checkCancellation()
            let mailboxes = try store.mailboxes(in: account.id)
                .map { mailbox in
                    DetectedMailbox(
                        accountID: account.id,
                        placement: mailbox.id,
                        messageCount: -1
                    )
                }
                .sorted { $0.placement.localizedStandardCompare($1.placement) == .orderedAscending }
            mailboxTotal += mailboxes.count
            accounts.append(DetectedAccount(id: account.id, mailboxes: mailboxes))
        }

        accounts = try enrichAccountIdentities(accounts, store: store)
        accounts.sort { lhs, rhs in
            let left = lhs.displayName ?? lhs.id
            let right = rhs.displayName ?? rhs.id
            let name = left.localizedStandardCompare(right)
            if name != .orderedSame { return name == .orderedAscending }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        return IndexCatalogSnapshot(
            accounts: accounts,
            accountsCount: accounts.count,
            mailboxesCount: mailboxTotal,
            messagesCount: -1
        )
    }

    nonisolated static func catalogFromIndex(
        structure: IndexCatalogSnapshot?,
        indexedCounts: [String: Int],
        store: MailStore
    ) throws -> IndexCatalogSnapshot {
        let accounts = try store.accounts().map { account -> DetectedAccount in
            let mailboxes = try store.mailboxes(in: account.id)
                .map { mailbox -> DetectedMailbox in
                    let key = "\(account.id)/\(mailbox.id)"
                    let count = indexedCounts[key] ?? 0
                    return DetectedMailbox(
                        accountID: account.id,
                        placement: mailbox.id,
                        messageCount: count
                    )
                }
                .sorted { $0.placement.localizedStandardCompare($1.placement) == .orderedAscending }
            return DetectedAccount(id: account.id, mailboxes: mailboxes)
        }

        let enriched = try enrichAccountIdentities(accounts, store: store)
        .sorted { lhs, rhs in
            let left = lhs.displayName ?? lhs.id
            let right = rhs.displayName ?? rhs.id
            let name = left.localizedStandardCompare(right)
            if name != .orderedSame { return name == .orderedAscending }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }

        let mailboxTotal = enriched.reduce(0) { $0 + $1.mailboxes.count }
        let messageTotal = indexedCounts.values.reduce(0, +)
        return IndexCatalogSnapshot(
            accounts: enriched,
            accountsCount: enriched.count,
            mailboxesCount: mailboxTotal,
            messagesCount: messageTotal
        )
    }

    nonisolated static func scanCatalog(store: MailStore) throws -> IndexCatalogSnapshot {
        var accounts: [DetectedAccount] = []
        var mailboxTotal = 0
        var messageTotal = 0

        for account in try store.accounts() {
            try Task.checkCancellation()
            if MailGentLog.verbose {
                MailGentLog.trace("scan account \(account.id)")
            }
            let mailboxes = try store.mailboxes(in: account.id)
                .map { mailbox -> DetectedMailbox in
                    let count = try store.messageCount(in: account.id, mailbox: mailbox.id)
                    return DetectedMailbox(
                        accountID: account.id,
                        placement: mailbox.id,
                        messageCount: count
                    )
                }
                .sorted { $0.placement.localizedStandardCompare($1.placement) == .orderedAscending }
            mailboxTotal += mailboxes.count
            messageTotal += mailboxes.reduce(0) { $0 + $1.messageCount }
            accounts.append(DetectedAccount(id: account.id, mailboxes: mailboxes))
        }

        accounts = try enrichAccountIdentities(accounts, store: store)
        accounts.sort { lhs, rhs in
            let left = lhs.displayName ?? lhs.id
            let right = rhs.displayName ?? rhs.id
            let name = left.localizedStandardCompare(right)
            if name != .orderedSame { return name == .orderedAscending }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
        return IndexCatalogSnapshot(
            accounts: accounts,
            accountsCount: accounts.count,
            mailboxesCount: mailboxTotal,
            messagesCount: messageTotal
        )
    }

    nonisolated static func enrichAccountIdentities(
        _ accounts: [DetectedAccount],
        store: MailStore
    ) throws -> [DetectedAccount] {
        let lookup = MailAccountIdentityResolver.lookup(
            try MailAccountIdentityResolver.resolve(in: store)
        )
        return accounts.map { account in
            guard let identity = lookup[account.id] else { return account }
            var copy = account
            copy.displayName = identity.displayName
            copy.email = identity.email
            return copy
        }
    }
}

enum MailIndexWorkerError: Error {
    case notReady
}
