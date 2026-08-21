import Foundation

public struct IndexUpdateOutcome: Equatable, Sendable {
    public let newCount: Int
    public let freshness: IndexFreshness

    public init(newCount: Int, freshness: IndexFreshness) {
        self.newCount = newCount
        self.freshness = freshness
    }
}

/// Runs an incremental index update and returns the outcome. Used by MCP `update`.
public protocol IndexUpdating: Sendable {
    func update() throws -> IndexUpdateOutcome
}

/// Default updater: ingest on a concrete `MailboxIndex` (tests / single-connection hosts).
public final class LocalIndexUpdater: IndexUpdating, @unchecked Sendable {
    private let index: MailboxIndex
    private let lock = NSLock()

    public init(index: MailboxIndex) {
        self.index = index
    }

    public func update() throws -> IndexUpdateOutcome {
        lock.lock()
        defer { lock.unlock() }
        let result = try index.ingest()
        return IndexUpdateOutcome(newCount: result.new.count, freshness: try index.freshness())
    }
}

/// Bridges an async ingest onto the sync MCP tool surface.
public final class BlockingIndexUpdater: IndexUpdating, @unchecked Sendable {
    public typealias Work = @Sendable () async throws -> IndexUpdateOutcome

    private let work: Work
    private let lock = NSLock()

    public init(work: @escaping Work) {
        self.work = work
    }

    public func update() throws -> IndexUpdateOutcome {
        lock.lock()
        defer { lock.unlock() }

        let box = OutcomeBox()
        let sem = DispatchSemaphore(value: 0)
        Task {
            do {
                box.result = .success(try await work())
            } catch {
                box.result = .failure(error)
            }
            sem.signal()
        }
        sem.wait()
        switch box.result {
        case let .success(outcome):
            return outcome
        case let .failure(error):
            throw error
        case .none:
            throw MailboxIndexError.unreadable
        }
    }
}

private final class OutcomeBox: @unchecked Sendable {
    var result: Result<IndexUpdateOutcome, Error>?
}
