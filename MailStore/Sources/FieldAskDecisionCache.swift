import Foundation

/// Who may reuse a cached Ask Allow/Block for the same message + field.
public enum AskDecisionCacheShareScope: String, Sendable, Codable, CaseIterable {
    /// Only the deciding pairing `agentID` reuses the entry (MCP and CLI on that id share it).
    case perAgent
    /// Any paired agent may reuse another agent’s entry for the same message + field.
    case allAgents
}

/// Settings-driven policy for the short-lived field Ask cache on `get`.
public struct AskDecisionCachePolicy: Equatable, Sendable {
    public var enabled: Bool
    /// `nil` → until process quit (no wall-clock expiry).
    public var ttlSeconds: TimeInterval?
    public var shareScope: AskDecisionCacheShareScope

    public init(
        enabled: Bool = false,
        ttlSeconds: TimeInterval? = 3_600,
        shareScope: AskDecisionCacheShareScope = .perAgent
    ) {
        self.enabled = enabled
        self.ttlSeconds = ttlSeconds
        self.shareScope = shareScope
    }

    public static let disabled = AskDecisionCachePolicy(enabled: false)
}

/// In-memory Ask Allow/Block per field for one message (and agent, unless share scope is all).
/// Not a standing grant — TTL / quit / forget clears it. Consult only after Scope + overlays.
public final class FieldAskDecisionCache: @unchecked Sendable {
    public struct Key: Hashable, Sendable {
        public let agentID: String
        public let accountID: String
        public let placement: String
        public let messageID: String
        public let field: String

        public init(
            agentID: String,
            accountID: String,
            placement: String,
            messageID: String,
            field: String
        ) {
            self.agentID = agentID
            self.accountID = accountID
            self.placement = placement
            self.messageID = messageID
            self.field = field
        }
    }

    private struct Entry: Sendable {
        let decision: ConditionalAccessDecision
        let storedAt: Date
    }

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]

    public init() {}

    public func decision(
        agentID: String,
        accountID: String,
        placement: String,
        messageID: String,
        field: String,
        policy: AskDecisionCachePolicy,
        now: Date = Date()
    ) -> ConditionalAccessDecision? {
        guard policy.enabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        switch policy.shareScope {
        case .perAgent:
            let key = Key(
                agentID: agentID,
                accountID: accountID,
                placement: placement,
                messageID: messageID,
                field: field
            )
            return liveDecision(for: key, policy: policy, now: now)
        case .allAgents:
            for (key, entry) in entries {
                guard key.accountID == accountID,
                      key.placement == placement,
                      key.messageID == messageID,
                      key.field == field
                else { continue }
                if isLive(entry, policy: policy, now: now) {
                    return entry.decision
                }
            }
            return nil
        }
    }

    public func store(
        _ decision: ConditionalAccessDecision,
        agentID: String,
        accountID: String,
        placement: String,
        messageID: String,
        field: String,
        now: Date = Date()
    ) {
        let key = Key(
            agentID: agentID,
            accountID: accountID,
            placement: placement,
            messageID: messageID,
            field: field
        )
        lock.lock()
        entries[key] = Entry(decision: decision, storedAt: now)
        lock.unlock()
    }

    public func removeAll(forAgentID agentID: String) {
        lock.lock()
        entries = entries.filter { $0.key.agentID != agentID }
        lock.unlock()
    }

    public func removeAll() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }

    private func liveDecision(
        for key: Key,
        policy: AskDecisionCachePolicy,
        now: Date
    ) -> ConditionalAccessDecision? {
        guard let entry = entries[key], isLive(entry, policy: policy, now: now) else {
            return nil
        }
        return entry.decision
    }

    private func isLive(_ entry: Entry, policy: AskDecisionCachePolicy, now: Date) -> Bool {
        guard let ttl = policy.ttlSeconds else { return true }
        return now.timeIntervalSince(entry.storedAt) <= ttl
    }
}
