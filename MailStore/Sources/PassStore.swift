import Foundation

/// Codable snapshot for `passes.json` (definitions + Scope enablements).
public struct PassSnapshot: Equatable, Codable, Sendable {
    public var passes: [Pass]
    public var enablements: [PassEnablement]

    public init(passes: [Pass] = [], enablements: [PassEnablement] = []) {
        self.passes = passes
        self.enablements = enablements
    }
}

/// In-memory store for pass definitions and placement enablements.
public final class PassStore: @unchecked Sendable {
    private var passes: [Pass] = []
    private var enablements: [PassEnablement] = []
    private let lock = NSLock()

    public init() {}

    public func allPasses() -> [Pass] {
        lock.lock()
        defer { lock.unlock() }
        return passes
    }

    public func allEnablements() -> [PassEnablement] {
        lock.lock()
        defer { lock.unlock() }
        return enablements
    }

    public func snapshot() -> PassSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return PassSnapshot(passes: passes, enablements: enablements)
    }

    public func replace(with snapshot: PassSnapshot) {
        lock.lock()
        passes = snapshot.passes
        enablements = snapshot.enablements
        lock.unlock()
    }

    public func upsert(_ pass: Pass) {
        lock.lock()
        if let idx = passes.firstIndex(where: { $0.id == pass.id }) {
            passes[idx] = pass
        } else {
            passes.append(pass)
        }
        lock.unlock()
    }

    public func removePass(id: String) {
        lock.lock()
        passes.removeAll { $0.id == id }
        enablements.removeAll { $0.passID == id }
        lock.unlock()
    }

    public func setEnablements(_ next: [PassEnablement]) {
        lock.lock()
        enablements = next
        lock.unlock()
    }

    public func setEnabled(_ enabled: Bool, passID: String, accountID: String, placement: String?) {
        lock.lock()
        enablements.removeAll {
            $0.passID == passID && $0.accountID == accountID && $0.placement == placement
        }
        if enabled {
            enablements.append(PassEnablement(passID: passID, accountID: accountID, placement: placement))
        }
        lock.unlock()
    }

    public func isEnabled(passID: String, accountID: String, placement: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return enablements.contains {
            $0.passID == passID && $0.accountID == accountID && $0.placement == placement
        }
    }
}
