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
}

struct IndexIncrementalSnapshot: Sendable {
    let catalog: IndexCatalogSnapshot
    let indexedCount: Int
    let placements: [Placement]
    let newCount: Int
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
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws -> IndexRebuildSnapshot {
        MailGentLog.trace("rebuild start root=\(store.root.path)")
        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: databaseURL)

        onProgress?("Opening index database…")
        let index = try MailboxIndex(store: store, databaseURL: databaseURL)

        try Task.checkCancellation()
        MailGentLog.trace("ingest begin")
        let ingest = try index.ingest { progress in
            let line = "ingest processed=\(progress.processed) indexed=\(progress.inserted) \(progress.accountID)/\(progress.mailboxID)"
            if progress.processed == 1 || progress.processed % 100 == 0 {
                MailGentLog.trace(line)
            }
            onProgress?(
                "Indexing \(progress.inserted) messages (\(progress.processed) scanned) · \(progress.mailboxID)"
            )
        }
        let api = ReadAPI(index: index)
        self.index = index
        self.api = api

        onProgress?("Finalizing index…")
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
        return IndexRebuildSnapshot(
            catalog: catalog,
            indexedCount: indexedCount,
            placements: placements,
            newCount: ingest.new.count
        )
    }

    func scanStructure(store: MailStore) async throws -> IndexCatalogSnapshot {
        try Self.scanCatalogStructure(store: store)
    }

    func incrementalIngest(onProgress: (@Sendable (String) -> Void)? = nil) async throws -> IndexIncrementalSnapshot {
        guard let index, let api else {
            throw MailIndexWorkerError.notReady
        }
        MailGentLog.trace("incremental ingest start")
        let ingest = try index.ingest { progress in
            onProgress?(
                "Checking mail · \(progress.inserted) new (\(progress.processed) scanned)"
            )
        }
        let indexedCount = try api.totalIndexed()
        let placements = try api.listPlacements()
        let catalog = try Self.catalogFromIndex(
            structure: nil,
            indexedCounts: try api.placementIndexedCounts(),
            store: index.store
        )
        MailGentLog.trace("incremental ingest done new=\(ingest.new.count) indexed=\(indexedCount)")
        return IndexIncrementalSnapshot(
            catalog: catalog,
            indexedCount: indexedCount,
            placements: placements,
            newCount: ingest.new.count
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

    func reset() {
        index = nil
        api = nil
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
