import Foundation

/// Result of submitting a conditional Ask into the pending registry.
public enum PendingAskSubmitResult: Equatable, Sendable {
    case created(askId: String, expiresAt: Date, pendingFields: [String])
    case deduped(askId: String, expiresAt: Date, pendingFields: [String])
}

/// Soft-wait result for `await_ask`.
public enum PendingAskAwaitResult: Equatable, Sendable {
    case stillAwaiting
    case allow(fields: [String])
    case block(fields: [String])
    case expired
    case superseded
    case dismissed
    case unknown
}

/// Terminal human / hard / rematch decision for a pending Ask.
public enum PendingAskDecision: Equatable, Sendable {
    case allow
    case block
    case superseded
    /// Traffic-light / ⌘W close — not Block; never Remember-cached.
    case dismissed
}

/// Request fingerprint inputs for conditional Ask dedupe + lease.
public struct PendingAskRequest: Equatable, Sendable {
    public let agentID: String
    public let accountID: String
    public let placement: String
    public let messageID: String
    public let fields: [String]
    public let filename: String?

    public init(
        agentID: String,
        accountID: String,
        placement: String,
        messageID: String,
        fields: [String],
        filename: String? = nil
    ) {
        self.agentID = agentID
        self.accountID = accountID
        self.placement = placement
        self.messageID = messageID
        self.fields = fields
        self.filename = filename
    }
}

/// In-memory pending Conditional Ask: fingerprint dedupe, soft wait, hard expire, post-allow lease.
public final class PendingAskRegistry: @unchecked Sendable {
    public static let defaultHardTimeoutSeconds: TimeInterval = 3_600
    /// DEBUG builds allow 1 minute for dogfooding expiry; Release keeps 5 minutes.
    #if DEBUG
    public static let hardTimeoutMinSeconds: TimeInterval = 60
    #else
    public static let hardTimeoutMinSeconds: TimeInterval = 300
    #endif
    public static let hardTimeoutMaxSeconds: TimeInterval = 28_800
    public static let defaultSoftTimeoutSeconds: TimeInterval = 25
    public static let softTimeoutMinSeconds: TimeInterval = 1
    public static let softTimeoutMaxSeconds: TimeInterval = 120
    /// Keep terminal outcomes briefly so a late `await_ask` still sees them.
    public static let terminalRetentionSeconds: TimeInterval = 120

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<PendingAskAwaitResult, Never>
    }

    private enum Terminal: Equatable {
        case allow
        case block
        case expired
        case superseded
        case dismissed
    }

    private struct Lease {
        let fingerprint: String
        let agentID: String
    }

    private struct Entry {
        let askId: String
        let agentID: String
        let fingerprint: String
        let pendingFields: [String]
        let expiresAt: Date
        var terminal: Terminal?
        var lease: Lease?
        var waiters: [Waiter]
        var terminalAt: Date?
    }

    private let lock = NSLock()
    private var hardTimeoutSeconds: TimeInterval
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    private var entries: [String: Entry] = [:]
    private var fingerprintIndex: [String: String] = [:]
    private var expirationHandler: (@Sendable (String) -> Void)?
    private var expiryTasks: [String: Task<Void, Never>] = [:]

    public init(
        hardTimeoutSeconds: TimeInterval = PendingAskRegistry.defaultHardTimeoutSeconds,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await ContinuousClock().sleep(for: duration)
        }
    ) {
        self.hardTimeoutSeconds = Self.clampHardTimeout(hardTimeoutSeconds)
        self.now = now
        self.sleep = sleep
    }

    public static func clampHardTimeout(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, hardTimeoutMinSeconds), hardTimeoutMaxSeconds)
    }

    public static func clampSoftTimeout(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, softTimeoutMinSeconds), softTimeoutMaxSeconds)
    }

    /// Fingerprint for dedupe + lease: agent + message coordinates + sorted fields (+ filename).
    public static func fingerprint(for request: PendingAskRequest) -> String {
        let fields = request.fields
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "\u{1e}")
        let filename = (request.filename ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return [
            request.agentID,
            request.accountID,
            request.placement,
            request.messageID,
            fields,
            filename
        ].joined(separator: "\u{1f}")
    }

    public func setHardTimeoutSeconds(_ seconds: TimeInterval) {
        lock.lock()
        hardTimeoutSeconds = Self.clampHardTimeout(seconds)
        lock.unlock()
    }

    public func readHardTimeoutSeconds() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return hardTimeoutSeconds
    }

    public func setExpirationHandler(_ handler: (@Sendable (String) -> Void)?) {
        lock.lock()
        expirationHandler = handler
        lock.unlock()
    }

    @discardableResult
    public func submit(_ request: PendingAskRequest) -> PendingAskSubmitResult {
        expireIfNeeded()
        let fields = normalizedFields(request.fields)
        let fp = Self.fingerprint(for: request)
        lock.lock()
        if let existingID = fingerprintIndex[fp],
           let existing = entries[existingID],
           existing.terminal == nil
        {
            let expiresAt = existing.expiresAt
            let pending = existing.pendingFields
            lock.unlock()
            return .deduped(askId: existingID, expiresAt: expiresAt, pendingFields: pending)
        }
        let timeout = hardTimeoutSeconds
        let expiresAt = now().addingTimeInterval(timeout)
        let id = UUID().uuidString
        entries[id] = Entry(
            askId: id,
            agentID: request.agentID,
            fingerprint: fp,
            pendingFields: fields,
            expiresAt: expiresAt,
            terminal: nil,
            lease: nil,
            waiters: [],
            terminalAt: nil
        )
        fingerprintIndex[fp] = id
        lock.unlock()
        scheduleExpiry(id: id, expiresAt: expiresAt)
        return .created(askId: id, expiresAt: expiresAt, pendingFields: fields)
    }

    public func awaitDecision(
        askId: String,
        agentID: String,
        softTimeout: TimeInterval
    ) async -> PendingAskAwaitResult {
        expireIfNeeded()
        let soft = Self.clampSoftTimeout(softTimeout)
        switch peekAwaitState(askId: askId, agentID: agentID, soft: soft) {
        case let .finished(result):
            return result
        case let .needsWait(wait):
            let waiterID = UUID()
            return await withCheckedContinuation { continuation in
                let immediate = self.enqueueWaiter(
                    askId: askId,
                    agentID: agentID,
                    waiterID: waiterID,
                    continuation: continuation
                )
                if let immediate {
                    continuation.resume(returning: immediate)
                    return
                }
                Task { [weak self] in
                    try? await self?.sleep(.seconds(wait))
                    self?.softTimeout(askId: askId, waiterID: waiterID)
                }
            }
        }
    }

    /// Record a terminal human / rematch decision. Second resolve is a no-op.
    @discardableResult
    public func resolve(askId: String, decision: PendingAskDecision) -> Bool {
        lock.lock()
        guard var entry = entries[askId], entry.terminal == nil else {
            lock.unlock()
            return false
        }
        switch decision {
        case .allow:
            entry.terminal = .allow
            entry.lease = Lease(fingerprint: entry.fingerprint, agentID: entry.agentID)
        case .block:
            entry.terminal = .block
        case .superseded:
            entry.terminal = .superseded
        case .dismissed:
            entry.terminal = .dismissed
        }
        entry.terminalAt = now()
        let waiters = entry.waiters
        entry.waiters = []
        fingerprintIndex[entry.fingerprint] = nil
        let fields = entry.pendingFields
        let result: PendingAskAwaitResult = switch decision {
        case .allow: .allow(fields: fields)
        case .block: .block(fields: fields)
        case .superseded: .superseded
        case .dismissed: .dismissed
        }
        entries[askId] = entry
        cancelExpiryTaskLocked(id: askId)
        lock.unlock()

        for waiter in waiters {
            waiter.continuation.resume(returning: result)
        }
        scheduleTerminalCleanup(id: askId)
        return true
    }

    /// Supersede matching pending asks (rule rematch). Returns superseded askIds.
    @discardableResult
    public func supersedeMatching(where predicate: (PendingAskRequestSnapshot) -> Bool) -> [String] {
        expireIfNeeded()
        lock.lock()
        let candidates = entries.values.filter { $0.terminal == nil }.map(\.askId)
        lock.unlock()
        var superseded: [String] = []
        for id in candidates {
            guard let snap = snapshot(askId: id), predicate(snap) else { continue }
            if resolve(askId: id, decision: .superseded) {
                superseded.append(id)
            }
        }
        return superseded
    }

    /// Mark due asks expired (hard clock). Safe to call repeatedly.
    public func expireIfNeeded() {
        lock.lock()
        let due = entries.values
            .filter { $0.terminal == nil && $0.expiresAt <= now() }
            .map(\.askId)
        lock.unlock()
        for id in due {
            expire(id: id)
        }
        sweepTerminal()
    }

    public func agentID(for askId: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries[askId]?.agentID
    }

    public func expiresAt(askId: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return entries[askId]?.expiresAt
    }

    public func pendingFields(askId: String) -> [String]? {
        lock.lock()
        defer { lock.unlock() }
        return entries[askId]?.pendingFields
    }

    public func isExpired(askId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[askId]?.terminal == .expired
    }

    /// Claim the post-allow lease for an exact fingerprint + agent + askId.
    /// Idempotent within terminal retention / lease lifetime.
    public func claimLease(askId: String, agentID: String, request: PendingAskRequest) -> Bool {
        expireIfNeeded()
        let fp = Self.fingerprint(for: request)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[askId],
              entry.terminal == .allow,
              let lease = entry.lease,
              lease.agentID == agentID,
              entry.agentID == agentID,
              lease.fingerprint == fp
        else {
            return false
        }
        return true
    }

    /// Fresh-get auto-apply: only a retained **allow** lease short-circuits a new Ask.
    /// Block / expired / dismissed / superseded never suppress a re-prompt (Remember cache is separate).
    public func lookupTerminal(agentID: String, request: PendingAskRequest) -> PendingAskAwaitResult? {
        expireIfNeeded()
        let fp = Self.fingerprint(for: request)
        lock.lock()
        defer { lock.unlock() }
        for entry in entries.values where entry.agentID == agentID && entry.fingerprint == fp {
            guard entry.terminal == .allow else { continue }
            return .allow(fields: entry.pendingFields)
        }
        return nil
    }

    /// Claim allow-lease by fingerprint (agent re-get after `await_ask` allow, without askId).
    public func claimLease(agentID: String, request: PendingAskRequest) -> Bool {
        if case .allow = lookupTerminal(agentID: agentID, request: request) {
            return true
        }
        return false
    }

    public func snapshot(askId: String) -> PendingAskRequestSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[askId] else { return nil }
        return PendingAskRequestSnapshot(
            askId: entry.askId,
            agentID: entry.agentID,
            fingerprint: entry.fingerprint,
            pendingFields: entry.pendingFields,
            expiresAt: entry.expiresAt,
            isPending: entry.terminal == nil
        )
    }

    // MARK: - Private

    private enum PeekAwait {
        case finished(PendingAskAwaitResult)
        case needsWait(TimeInterval)
    }

    private func peekAwaitState(askId: String, agentID: String, soft: TimeInterval) -> PeekAwait {
        lock.lock()
        guard let entry = entries[askId] else {
            lock.unlock()
            return .finished(.unknown)
        }
        if entry.agentID != agentID {
            lock.unlock()
            return .finished(.unknown)
        }
        if let terminal = entry.terminal {
            lock.unlock()
            return .finished(awaitResult(terminal: terminal, fields: entry.pendingFields))
        }
        let remainingHard = entry.expiresAt.timeIntervalSince(now())
        lock.unlock()
        if remainingHard <= 0 {
            expire(id: askId)
            return .finished(.expired)
        }
        return .needsWait(min(soft, remainingHard))
    }

    private func enqueueWaiter(
        askId: String,
        agentID: String,
        waiterID: UUID,
        continuation: CheckedContinuation<PendingAskAwaitResult, Never>
    ) -> PendingAskAwaitResult? {
        lock.lock()
        defer { lock.unlock() }
        guard let live = entries[askId] else { return .unknown }
        if live.agentID != agentID { return .unknown }
        if let terminal = live.terminal {
            return awaitResult(terminal: terminal, fields: live.pendingFields)
        }
        var entry = live
        entry.waiters.append(Waiter(id: waiterID, continuation: continuation))
        entries[askId] = entry
        return nil
    }

    private func softTimeout(askId: String, waiterID: UUID) {
        lock.lock()
        guard var entry = entries[askId] else {
            lock.unlock()
            return
        }
        guard let idx = entry.waiters.firstIndex(where: { $0.id == waiterID }) else {
            lock.unlock()
            return
        }
        if let terminal = entry.terminal {
            let waiter = entry.waiters.remove(at: idx)
            entries[askId] = entry
            lock.unlock()
            waiter.continuation.resume(returning: awaitResult(terminal: terminal, fields: entry.pendingFields))
            return
        }
        if entry.expiresAt <= now() {
            lock.unlock()
            expire(id: askId)
            return
        }
        let waiter = entry.waiters.remove(at: idx)
        entries[askId] = entry
        lock.unlock()
        waiter.continuation.resume(returning: .stillAwaiting)
    }

    private func expire(id: String) {
        lock.lock()
        guard var entry = entries[id], entry.terminal == nil else {
            lock.unlock()
            return
        }
        entry.terminal = .expired
        entry.terminalAt = now()
        let waiters = entry.waiters
        entry.waiters = []
        fingerprintIndex[entry.fingerprint] = nil
        entries[id] = entry
        cancelExpiryTaskLocked(id: id)
        let handler = expirationHandler
        lock.unlock()

        for waiter in waiters {
            waiter.continuation.resume(returning: .expired)
        }
        handler?(id)
        scheduleTerminalCleanup(id: id)
    }

    private func scheduleExpiry(id: String, expiresAt: Date) {
        let delay = expiresAt.timeIntervalSince(now())
        let task = Task { [weak self] in
            if delay > 0 {
                try? await self?.sleep(.seconds(delay))
            }
            self?.expireIfNeeded()
        }
        lock.lock()
        expiryTasks[id]?.cancel()
        expiryTasks[id] = task
        lock.unlock()
    }

    private func cancelExpiryTaskLocked(id: String) {
        expiryTasks[id]?.cancel()
        expiryTasks[id] = nil
    }

    private func scheduleTerminalCleanup(id: String) {
        Task { [weak self] in
            try? await self?.sleep(.seconds(Self.terminalRetentionSeconds))
            self?.sweepTerminal()
            _ = id
        }
    }

    private func sweepTerminal() {
        lock.lock()
        let cutoff = now().addingTimeInterval(-Self.terminalRetentionSeconds)
        let stale = entries.values
            .filter { entry in
                guard let terminalAt = entry.terminalAt else { return false }
                return terminalAt <= cutoff
            }
            .map(\.askId)
        for id in stale {
            entries[id] = nil
            cancelExpiryTaskLocked(id: id)
        }
        lock.unlock()
    }

    private func awaitResult(terminal: Terminal, fields: [String]) -> PendingAskAwaitResult {
        switch terminal {
        case .allow: .allow(fields: fields)
        case .block: .block(fields: fields)
        case .expired: .expired
        case .superseded: .superseded
        case .dismissed: .dismissed
        }
    }

    private func normalizedFields(_ fields: [String]) -> [String] {
        Array(
            Set(
                fields
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted()
    }
}

/// Read-only snapshot for rematch predicates / UI.
public struct PendingAskRequestSnapshot: Equatable, Sendable {
    public let askId: String
    public let agentID: String
    public let fingerprint: String
    public let pendingFields: [String]
    public let expiresAt: Date
    public let isPending: Bool
}
