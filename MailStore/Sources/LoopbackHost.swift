import Foundation

/// Thread-safe loopback session: auth + optional read gateway + index lifecycle.
public final class LoopbackHost: @unchecked Sendable {
    public let pairing: Pairing
    public let audit: AuditLog?
    public let grants: GrantGate
    public let ledger: DraftLedger

    private let lock = NSLock()
    private var gateway: AgentReadAPI?
    private var indexUpdater: (any IndexUpdating)?
    private var sourceController: (any MailSourceControlling)?
    private var appleMailOpener: (any AppleMailOpening)?
    /// Off by default — agents may call MCP `open_in_mail` only when the companion enables it.
    private var agentMayOpenInMail = false
    private var indexState = LoopbackIndexSnapshot.notStarted

    public init(
        pairing: Pairing,
        audit: AuditLog? = nil,
        grants: GrantGate,
        ledger: DraftLedger = DraftLedger()
    ) {
        self.pairing = pairing
        self.audit = audit
        self.grants = grants
        self.ledger = ledger
    }

    public func authenticate(_ credential: String?) throws -> PairedAgent {
        try pairing.authenticate(credential: credential)
    }

    public func snapshot() -> LoopbackIndexSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return indexState
    }

    public func readGateway() -> AgentReadAPI? {
        lock.lock()
        defer { lock.unlock() }
        return gateway
    }

    public func readIndexUpdater() -> (any IndexUpdating)? {
        lock.lock()
        defer { lock.unlock() }
        return indexUpdater
    }

    public func readSourceController() -> (any MailSourceControlling)? {
        lock.lock()
        defer { lock.unlock() }
        return sourceController
    }

    public func readAppleMailOpener() -> (any AppleMailOpening)? {
        lock.lock()
        defer { lock.unlock() }
        return appleMailOpener
    }

    public func readAgentMayOpenInMail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return agentMayOpenInMail
    }

    public func setGateway(_ gateway: AgentReadAPI?, indexUpdater: (any IndexUpdating)?) {
        lock.lock()
        self.gateway = gateway
        self.indexUpdater = indexUpdater
        lock.unlock()
    }

    public func setSourceController(_ sourceController: (any MailSourceControlling)?) {
        lock.lock()
        self.sourceController = sourceController
        lock.unlock()
    }

    public func setAppleMailOpener(_ opener: (any AppleMailOpening)?) {
        lock.lock()
        self.appleMailOpener = opener
        lock.unlock()
    }

    public func setAgentMayOpenInMail(_ allowed: Bool) {
        lock.lock()
        agentMayOpenInMail = allowed
        lock.unlock()
    }

    public func setIndexState(_ state: LoopbackIndexSnapshot) {
        lock.lock()
        indexState = state
        lock.unlock()
    }
}
