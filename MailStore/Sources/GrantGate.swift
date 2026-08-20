import Foundation

public struct Grant: Equatable, Sendable {
    public let agentID: String
    public let accountID: String
    /// nil means all placements in the account (snapshot of that account only).
    public let placement: String?

    public init(agentID: String, accountID: String, placement: String? = nil) {
        self.agentID = agentID
        self.accountID = accountID
        self.placement = placement
    }

    public func allows(accountID: String, placement: String) -> Bool {
        guard self.accountID == accountID else { return false }
        guard let required = self.placement else { return true }
        return required == placement
    }
}

public final class GrantGate: @unchecked Sendable {
    private var grants: [Grant] = []
    private let lock = NSLock()

    public init() {}

    public func allow(agentID: String, accountID: String, placement: String? = nil) throws {
        let grant = Grant(agentID: agentID, accountID: accountID, placement: placement)
        lock.lock()
        grants.removeAll {
            $0.agentID == agentID && $0.accountID == accountID && $0.placement == placement
        }
        grants.append(grant)
        lock.unlock()
    }

    public func revokeAll(agentID: String) {
        lock.lock()
        grants.removeAll { $0.agentID == agentID }
        lock.unlock()
    }

    public func allows(agentID: String, accountID: String, placement: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return grants.contains {
            $0.agentID == agentID && $0.allows(accountID: accountID, placement: placement)
        }
    }

    public func filter(_ messages: [IndexedMessage], agentID: String) -> [IndexedMessage] {
        messages.filter { allows(agentID: agentID, accountID: $0.accountID, placement: $0.placement) }
    }

    public func filter(_ placements: [Placement], agentID: String) -> [Placement] {
        placements.filter { allows(agentID: agentID, accountID: $0.accountID, placement: $0.id) }
    }
}
