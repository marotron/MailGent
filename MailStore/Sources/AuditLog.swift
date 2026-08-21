import Foundation

public enum AuditKind: String, Equatable, Sendable {
    case pair
    case search
    case get
    case createDraft
    case updateDraft
    case updateIndex
    case revoke
}

public struct AuditEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: AuditKind
    public let agentID: String
    public let agentName: String
    public let detail: String
    public let at: Date

    public init(
        id: String = UUID().uuidString,
        kind: AuditKind,
        agentID: String,
        agentName: String,
        detail: String = "",
        at: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.agentID = agentID
        self.agentName = agentName
        self.detail = detail
        self.at = at
    }
}

public final class AuditLog: @unchecked Sendable {
    private var storage: [AuditEntry] = []
    private let lock = NSLock()

    public init() {}

    public func append(_ entry: AuditEntry) {
        lock.lock()
        storage.append(entry)
        lock.unlock()
    }

    public func entries() -> [AuditEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
