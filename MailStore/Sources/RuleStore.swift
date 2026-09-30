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

    public func setEnabled(_ enabled: Bool, ruleID: String, accountID: String, placement: String?) {
        lock.lock()
        enablements.removeAll {
            $0.ruleID == ruleID && $0.accountID == accountID && $0.placement == placement
        }
        if enabled {
            enablements.append(RuleEnablement(ruleID: ruleID, accountID: accountID, placement: placement))
        }
        lock.unlock()
    }

    public func isEnabled(ruleID: String, accountID: String, placement: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enablements.contains {
            $0.ruleID == ruleID && $0.accountID == accountID && $0.placement == placement
        }
    }
}
