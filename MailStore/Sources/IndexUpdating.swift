import Foundation

public struct IndexUpdateOutcome: Equatable, Sendable {
    public let newCount: Int
    public let removedCount: Int
    public let freshness: IndexFreshness

    public init(newCount: Int, removedCount: Int = 0, freshness: IndexFreshness) {
        self.newCount = newCount
        self.removedCount = removedCount
        self.freshness = freshness
    }
}

/// Runs an incremental index update and returns the outcome. Used by MCP `update`.
public protocol IndexUpdating: Sendable {
    func update() async throws -> IndexUpdateOutcome
}

/// Default updater: ingest on a concrete `MailboxIndex` (tests / single-connection hosts).
public final class LocalIndexUpdater: IndexUpdating, @unchecked Sendable {
    private let index: MailboxIndex
    private let lock = NSLock()

    public init(index: MailboxIndex) {
        self.index = index
    }

    public func update() async throws -> IndexUpdateOutcome {
        try ingestLocked()
    }

    private func ingestLocked() throws -> IndexUpdateOutcome {
        lock.lock()
        defer { lock.unlock() }
        let result = try index.ingest()
        return IndexUpdateOutcome(
            newCount: result.new.count,
            removedCount: result.removed.count,
            freshness: try index.freshness()
        )
    }
}

/// Forwards companion ingest into the MCP `update` tool.
public final class BlockingIndexUpdater: IndexUpdating, @unchecked Sendable {
    public typealias Work = @Sendable () async throws -> IndexUpdateOutcome

    private let work: Work

    public init(work: @escaping Work) {
        self.work = work
    }

    public func update() async throws -> IndexUpdateOutcome {
        try await work()
    }
}
