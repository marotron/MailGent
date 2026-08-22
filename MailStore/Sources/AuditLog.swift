import Foundation

public enum AuditKind: String, Equatable, Sendable {
    case pair
    case search
    case list
    case listPlacements
    case get
    case createDraft
    case updateDraft
    case updateIndex
    case status
    case setSource = "set_source"
    case revoke
}

public enum AuditOutcome: Equatable, Sendable {
    case ok
    case error(String)
}

public struct AuditMessageRef: Equatable, Hashable, Sendable {
    public let accountID: String
    public let placement: String
    public let id: String
    public let subject: String
    public let from: String
    public let date: String

    public init(
        accountID: String,
        placement: String,
        id: String,
        subject: String,
        from: String,
        date: String
    ) {
        self.accountID = accountID
        self.placement = placement
        self.id = id
        self.subject = subject
        self.from = from
        self.date = date
    }

    public var rowID: String { "\(accountID)/\(placement)/\(id)" }
}

public struct AuditPlacementRef: Equatable, Hashable, Sendable {
    public let accountID: String
    public let placement: String

    public init(accountID: String, placement: String) {
        self.accountID = accountID
        self.placement = placement
    }

    public var rowID: String { "\(accountID)/\(placement)" }
}

public struct AuditEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: AuditKind
    public let agentID: String
    public let agentName: String
    public let detail: String
    public let at: Date
    public let finishedAt: Date?
    public let requestSummary: String
    public let responseSummary: String
    public let messages: [AuditMessageRef]
    public let placements: [AuditPlacementRef]
    public let outcome: AuditOutcome

    public init(
        id: String = UUID().uuidString,
        kind: AuditKind,
        agentID: String,
        agentName: String,
        detail: String = "",
        at: Date = Date(),
        finishedAt: Date? = nil,
        requestSummary: String = "",
        responseSummary: String = "",
        messages: [AuditMessageRef] = [],
        placements: [AuditPlacementRef] = [],
        outcome: AuditOutcome = .ok
    ) {
        self.id = id
        self.kind = kind
        self.agentID = agentID
        self.agentName = agentName
        self.detail = detail
        self.at = at
        self.finishedAt = finishedAt
        self.requestSummary = requestSummary
        self.responseSummary = responseSummary
        self.messages = messages
        self.placements = placements
        self.outcome = outcome
    }

    public var duration: TimeInterval? {
        guard let finishedAt else { return nil }
        return finishedAt.timeIntervalSince(at)
    }
}

public final class AuditLog: @unchecked Sendable {
    public static let capacity = 50
    public static let messageRefCap = 25

    private var storage: [AuditEntry] = []
    private let lock = NSLock()
    /// Fired after each append (any thread). Bridge uses this to bump UI revision.
    public var onChange: (@Sendable () -> Void)?

    public init() {}

    public func append(_ entry: AuditEntry) {
        lock.lock()
        storage.append(entry)
        if storage.count > Self.capacity {
            storage.removeFirst(storage.count - Self.capacity)
        }
        lock.unlock()
        onChange?()
    }

    public func entries() -> [AuditEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

extension AuditMessageRef {
    public init(_ message: IndexedMessage) {
        self.init(
            accountID: message.accountID,
            placement: message.placement,
            id: message.id,
            subject: message.subject,
            from: message.from,
            date: message.date
        )
    }

    public init(_ message: ReadMessage) {
        self.init(
            accountID: message.accountID,
            placement: message.placement,
            id: message.id,
            subject: message.subject,
            from: message.from,
            date: message.date
        )
    }
}
