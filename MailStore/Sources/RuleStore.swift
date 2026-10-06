import Foundation

/// Codable snapshot for `rules.json` (definitions + Scope enablements).
public struct RuleSnapshot: Equatable, Codable, Sendable {
    public var rules: [GrantRule]
    public var enablements: [RuleEnablement]

    public init(rules: [GrantRule] = [], enablements: [RuleEnablement] = []) {
        self.rules = rules
        self.enablements = enablements
    }
}

/// In-memory store for rule definitions and placement enablements.
public final class RuleStore: @unchecked Sendable {
    private var rules: [GrantRule] = []
    private var enablements: [RuleEnablement] = []
    private let lock = NSLock()

    public init() {}

    public func allRules() -> [GrantRule] {
        lock.lock()
        defer { lock.unlock() }
        return rules
    }

    public func allEnablements() -> [RuleEnablement] {
        lock.lock()
        defer { lock.unlock() }
        return enablements
    }

    public func snapshot() -> RuleSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return RuleSnapshot(rules: rules, enablements: enablements)
    }

    public func replace(with snapshot: RuleSnapshot) {
        lock.lock()
        rules = snapshot.rules
        enablements = snapshot.enablements
        lock.unlock()
    }

    public func upsert(_ rule: GrantRule) {
        lock.lock()
        if let idx = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[idx] = rule
        } else {
            rules.append(rule)
        }
        lock.unlock()
    }

    public func removeRule(id: String) {
        lock.lock()
        rules.removeAll { $0.id == id }
        enablements.removeAll { $0.ruleID == id }
        lock.unlock()
    }

    public func setEnablements(_ next: [RuleEnablement]) {
        lock.lock()
        enablements = next
        lock.unlock()
    }

    public func setEnabled(
        _ enabled: Bool,
        ruleID: String,
        agentID: String,
        accountID: String,
        placement: String?
    ) {
        lock.lock()
        // Drop exact row and any legacy shared (empty agentID) row for this placement.
        enablements.removeAll {
            $0.ruleID == ruleID
                && $0.accountID == accountID
                && $0.placement == placement
                && ($0.agentID == agentID || $0.agentID.isEmpty)
        }
        if enabled {
            enablements.append(
                RuleEnablement(ruleID: ruleID, agentID: agentID, accountID: accountID, placement: placement)
            )
        }
        lock.unlock()
    }

    public func isEnabled(
        ruleID: String,
        agentID: String,
        accountID: String,
        placement: String?
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enablements.contains {
            $0.ruleID == ruleID
                && ($0.agentID.isEmpty || $0.agentID == agentID)
                && $0.accountID == accountID
                && $0.placement == placement
        }
    }

    public func removeEnablements(agentID: String) {
        lock.lock()
        enablements.removeAll { $0.agentID == agentID }
        lock.unlock()
    }

    /// Expand legacy shared enablements (`agentID == ""`) into one row per known agent.
    public static func migrateLegacySharedEnablements(
        _ snapshot: RuleSnapshot,
        agentIDs: [String]
    ) -> RuleSnapshot {
        guard !agentIDs.isEmpty else { return snapshot }
        var next: [RuleEnablement] = []
        var seen = Set<String>()
        func key(_ e: RuleEnablement) -> String {
            "\(e.ruleID)|\(e.agentID)|\(e.accountID)|\(e.placement ?? "*")"
        }
        for e in snapshot.enablements {
            if e.agentID.isEmpty {
                for id in agentIDs {
                    let row = RuleEnablement(
                        ruleID: e.ruleID,
                        agentID: id,
                        accountID: e.accountID,
                        placement: e.placement
                    )
                    let k = key(row)
                    if seen.insert(k).inserted { next.append(row) }
                }
            } else {
                let k = key(e)
                if seen.insert(k).inserted { next.append(e) }
            }
        }
        return RuleSnapshot(rules: snapshot.rules, enablements: next)
    }
}
