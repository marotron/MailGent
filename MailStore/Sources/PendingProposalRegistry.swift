import Foundation

/// Result of submitting a send proposal into the pending registry.
public enum PendingProposalSubmitResult: Equatable, Sendable {
    case created(proposalId: String, expiresAt: Date, proposal: SendProposal)
    case deduped(proposalId: String, expiresAt: Date, proposal: SendProposal)
}

/// Soft-wait result for `await_propose_send`.
public enum PendingProposalAwaitResult: Equatable, Sendable {
    case stillAwaiting
    case decided(SendProposalDecision)
    case expired
    case unknown
}

/// In-memory pending `propose_send` proposals: fingerprint dedupe, soft wait, hard expire.
public final class PendingProposalRegistry: @unchecked Sendable {
    public static let defaultHardTimeoutSeconds: TimeInterval = 3_600
    public static let hardTimeoutMinSeconds: TimeInterval = 300
    public static let hardTimeoutMaxSeconds: TimeInterval = 28_800
    public static let defaultSoftTimeoutSeconds: TimeInterval = 60
    public static let softTimeoutMinSeconds: TimeInterval = 1
    public static let softTimeoutMaxSeconds: TimeInterval = 120
    /// Keep terminal outcomes briefly so a late `await_propose_send` still sees them.
    public static let terminalRetentionSeconds: TimeInterval = 120
    /// Revise and look round-trips per proposal. The original hard expiry is not reset.
    public static let revisionCap = 5

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<PendingProposalAwaitResult, Never>
    }

    private struct Entry {
        let proposalId: String
        let agentID: String
        var fingerprint: String
        var proposal: SendProposal
        let expiresAt: Date
        var decision: SendProposalDecision?
        /// One-shot outcome for the next `await_propose_send`. Not terminal.
        var pendingInterim: SendProposalDecision?
        var agentPayload: ProposalAgentPayload?
        var awaitingRevision: Bool
        /// Survives the one-shot interim delivery so `revises` can still be accepted.
        var revisionKind: SendProposalDecision?
        var revisionRoundTrips: Int
        var revisionResults: [ProposalInstructionResult]
        var expired: Bool
        /// Single-flight deliver: idle → inFlight → succeeded (or back to idle on failure).
        var deliveryPhase: DeliveryPhase
        var waiters: [Waiter]
        var terminalAt: Date?
    }

    private enum DeliveryPhase: Equatable {
        case idle
        case inFlight
        case succeeded
    }

    private let lock = NSLock()
    private var hardTimeoutSeconds: TimeInterval
    private let now: @Sendable () -> Date
    private var entries: [String: Entry] = [:]
    private var fingerprintIndex: [String: String] = [:]
    private var expirationHandler: (@Sendable (String) -> Void)?
    private var revisionHandler: (@Sendable (String, SendProposal, [ProposalInstructionResult]) -> Void)?
    private var expiryTasks: [String: Task<Void, Never>] = [:]

    public init(
        hardTimeoutSeconds: TimeInterval = PendingProposalRegistry.defaultHardTimeoutSeconds,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.hardTimeoutSeconds = Self.clampHardTimeout(hardTimeoutSeconds)
        self.now = now
    }

    public static func clampHardTimeout(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, hardTimeoutMinSeconds), hardTimeoutMaxSeconds)
    }

    public static func clampSoftTimeout(_ seconds: TimeInterval) -> TimeInterval {
        min(max(seconds, softTimeoutMinSeconds), softTimeoutMaxSeconds)
    }

    /// Fingerprint for dedupe: agent + normalized to/cc/bcc/sender/subject/body (not context).
    public static func fingerprint(
        agentID: String,
        to: [String],
        cc: [String],
        bcc: [String],
        sender: String?,
        subject: String,
        body: String
    ) -> String {
        func norm(_ s: String) -> String {
            s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        func list(_ values: [String]) -> String {
            values.map(norm).joined(separator: "\u{1e}")
        }
        return [
            agentID,
            list(to),
            list(cc),
            list(bcc),
            norm(sender ?? ""),
            norm(subject),
            body.trimmingCharacters(in: .whitespacesAndNewlines)
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
    public func submit(agentID: String, proposal: SendProposal) -> PendingProposalSubmitResult {
        expireIfNeeded()
        let fp = Self.fingerprint(
            agentID: agentID,
            to: proposal.to,
            cc: proposal.cc,
            bcc: proposal.bcc,
            sender: proposal.sender,
            subject: proposal.subject,
            body: proposal.body
        )
        lock.lock()
        if let existingID = fingerprintIndex[fp],
           var existing = entries[existingID],
           !existing.expired,
           existing.decision == nil
        {
            existing.proposal = proposal
            entries[existingID] = existing
            let expiresAt = existing.expiresAt
            let stored = existing.proposal
            lock.unlock()
            return .deduped(proposalId: existingID, expiresAt: expiresAt, proposal: stored)
        }
        let timeout = hardTimeoutSeconds
        let expiresAt = now().addingTimeInterval(timeout)
        let id = proposal.id
        entries[id] = Entry(
            proposalId: id,
            agentID: agentID,
            fingerprint: fp,
            proposal: proposal,
            expiresAt: expiresAt,
            decision: nil,
            pendingInterim: nil,
            agentPayload: nil,
            awaitingRevision: false,
            revisionKind: nil,
            revisionRoundTrips: 0,
            revisionResults: [],
            expired: false,
            deliveryPhase: .idle,
            waiters: [],
            terminalAt: nil
        )
        fingerprintIndex[fp] = id
        lock.unlock()
        scheduleExpiry(id: id, expiresAt: expiresAt)
        return .created(proposalId: id, expiresAt: expiresAt, proposal: proposal)
    }

    public func awaitDecision(id: String, softTimeout: TimeInterval) async -> PendingProposalAwaitResult {
        expireIfNeeded()
        let soft = Self.clampSoftTimeout(softTimeout)
        switch peekAwaitState(id: id, soft: soft) {
        case let .finished(result):
            return result
        case let .needsWait(wait):
            let waiterID = UUID()
            return await withCheckedContinuation { continuation in
                let immediate = self.enqueueWaiter(id: id, waiterID: waiterID, continuation: continuation)
                if let immediate {
                    continuation.resume(returning: immediate)
                    return
                }
                Task { [weak self] in
                    let ns = UInt64(wait * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: ns)
                    self?.softTimeout(id: id, waiterID: waiterID)
                }
            }
        }
    }

    private enum PeekAwait {
        case finished(PendingProposalAwaitResult)
        case needsWait(TimeInterval)
    }

    private func peekAwaitState(id: String, soft: TimeInterval) -> PeekAwait {
        lock.lock()
        guard var entry = entries[id] else {
            lock.unlock()
            return .finished(.unknown)
        }
        if entry.expired {
            lock.unlock()
            return .finished(.expired)
        }
        if let decision = entry.decision {
            lock.unlock()
            return .finished(.decided(decision))
        }
        if let interim = entry.pendingInterim {
            entry.pendingInterim = nil
            entries[id] = entry
            lock.unlock()
            return .finished(.decided(interim))
        }
        let remainingHard = entry.expiresAt.timeIntervalSince(now())
        lock.unlock()
        if remainingHard <= 0 {
            expire(id: id)
            return .finished(.expired)
        }
        return .needsWait(min(soft, remainingHard))
    }

    /// Returns a terminal result if the entry finished between peek and enqueue; otherwise nil (waiter stored).
    private func enqueueWaiter(
        id: String,
        waiterID: UUID,
        continuation: CheckedContinuation<PendingProposalAwaitResult, Never>
    ) -> PendingProposalAwaitResult? {
        lock.lock()
        defer { lock.unlock() }
        guard var live = entries[id] else { return .unknown }
        if live.expired { return .expired }
        if let decision = live.decision { return .decided(decision) }
        if let interim = live.pendingInterim {
            live.pendingInterim = nil
            entries[id] = live
            return .decided(interim)
        }
        live.waiters.append(Waiter(id: waiterID, continuation: continuation))
        entries[id] = live
        return nil
    }

    /// Record a terminal human decision (`send`, `openInMail`, `cancel`). Second resolve is a no-op.
    @discardableResult
    public func resolve(
        id: String,
        decision: SendProposalDecision,
        payload: ProposalAgentPayload? = nil
    ) -> Bool {
        lock.lock()
        guard var entry = entries[id], !entry.expired, entry.decision == nil else {
            lock.unlock()
            return false
        }
        entry.decision = decision
        entry.pendingInterim = nil
        entry.awaitingRevision = false
        entry.revisionKind = nil
        switch decision {
        case .send, .reviseRequested, .attentionRequested:
            if let payload { entry.agentPayload = payload }
        case .cancel, .openInMail:
            entry.agentPayload = payload
        }
        entry.terminalAt = now()
        let waiters = entry.waiters
        entry.waiters = []
        fingerprintIndex[entry.fingerprint] = nil
        entries[id] = entry
        cancelExpiryTaskLocked(id: id)
        lock.unlock()

        for waiter in waiters {
            waiter.continuation.resume(returning: .decided(decision))
        }
        scheduleTerminalCleanup(id: id)
        return true
    }

    /// Mark due proposals expired (hard clock). Safe to call repeatedly.
    public func expireIfNeeded() {
        lock.lock()
        let due = entries.values
            .filter { !$0.expired && $0.decision == nil && $0.expiresAt <= now() }
            .map(\.proposalId)
        lock.unlock()
        for id in due {
            expire(id: id)
        }
        sweepTerminal()
    }

    public func agentID(for id: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.agentID
    }

    public func proposal(id: String) -> SendProposal? {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.proposal
    }

    public func expiresAt(id: String) -> Date? {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.expiresAt
    }

    /// Claim the one-shot deliver. Fails when expired, in-flight, or already succeeded.
    ///
    /// Decision may still be `nil` when the confirm UI owns the Send handoff (claim → AppleScript
    /// → mark succeeded, then resolve). `await_propose_send` claims after a decision as before
    /// (including `.cancel`, which only marks the claim succeeded).
    public func claimDelivery(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[id],
              !entry.expired,
              entry.deliveryPhase == .idle
        else {
            return false
        }
        entry.deliveryPhase = .inFlight
        entries[id] = entry
        return true
    }

    /// After a failed AppleScript (or pre-deliver check), free the claim so a later await can retry.
    public func releaseDeliveryClaim(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[id], entry.deliveryPhase == .inFlight else { return }
        entry.deliveryPhase = .idle
        entries[id] = entry
    }

    /// Mark deliver finished successfully (or cancel handled). Idempotent claim stays closed.
    public func markDeliverySucceeded(id: String) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[id], entry.deliveryPhase == .inFlight else { return }
        entry.deliveryPhase = .succeeded
        entries[id] = entry
    }

    public func isDeliverySucceeded(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.deliveryPhase == .succeeded
    }

    public func isExpired(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.expired == true
    }

    /// Keep an agent payload on the open proposal until `resolve` or the next interim.
    public func stagePayload(id: String, payload: ProposalAgentPayload) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[id], !entry.expired, entry.decision == nil else { return }
        entry.agentPayload = payload
        entries[id] = entry
    }

    /// Replace the draft that delivery will use. Does not decide or reset the deadline.
    public func updateDraft(id: String, proposal: SendProposal) {
        lock.lock()
        guard var entry = entries[id], !entry.expired, entry.decision == nil, proposal.id == id else {
            lock.unlock()
            return
        }
        fingerprintIndex[entry.fingerprint] = nil
        let fp = Self.fingerprint(
            agentID: entry.agentID,
            to: proposal.to,
            cc: proposal.cc,
            bcc: proposal.bcc,
            sender: proposal.sender,
            subject: proposal.subject,
            body: proposal.body
        )
        entry.fingerprint = fp
        entry.proposal = proposal
        fingerprintIndex[fp] = id
        entries[id] = entry
        lock.unlock()
    }

    public func agentPayload(id: String) -> ProposalAgentPayload? {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.agentPayload
    }

    public func revisionRoundTrips(id: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.revisionRoundTrips ?? 0
    }

    public func revisionResults(id: String) -> [ProposalInstructionResult] {
        lock.lock()
        defer { lock.unlock() }
        return entries[id]?.revisionResults ?? []
    }

    /// Further Ask to revise / Ask to look. Send, Open in Mail, and Cancel stay available.
    public func canRequestRevision(id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[id], !entry.expired, entry.decision == nil else { return false }
        return entry.revisionRoundTrips < Self.revisionCap
    }

    /// Proposal ids for this agent that are waiting on `propose_send` with `revises`.
    public func awaitingRevisionIDs(agentID: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries.values
            .filter {
                $0.agentID == agentID
                    && $0.awaitingRevision
                    && !$0.expired
                    && $0.decision == nil
            }
            .map(\.proposalId)
            .sorted()
    }

    public func setRevisionHandler(
        _ handler: (@Sendable (String, SendProposal, [ProposalInstructionResult]) -> Void)?
    ) {
        lock.lock()
        revisionHandler = handler
        lock.unlock()
    }

    /// Wake `await_propose_send` with revise or attention. Does not deliver mail, cancel, or move the deadline.
    @discardableResult
    public func publishInterim(
        id: String,
        decision: SendProposalDecision,
        payload: ProposalAgentPayload
    ) -> Bool {
        guard decision == .reviseRequested || decision == .attentionRequested else { return false }
        lock.lock()
        guard var entry = entries[id], !entry.expired, entry.decision == nil else {
            lock.unlock()
            return false
        }
        guard entry.revisionRoundTrips < Self.revisionCap else {
            lock.unlock()
            return false
        }
        entry.revisionRoundTrips += 1
        entry.awaitingRevision = true
        entry.revisionKind = decision
        entry.agentPayload = payload
        entry.pendingInterim = decision
        let waiters = entry.waiters
        entry.waiters = []
        if !waiters.isEmpty {
            entry.pendingInterim = nil
        }
        let expiresAt = entry.expiresAt
        entries[id] = entry
        lock.unlock()
        _ = expiresAt
        for waiter in waiters {
            waiter.continuation.resume(returning: .decided(decision))
        }
        return true
    }

    /// Swap the draft in place after `propose_send` `revises`. Same id, same hard deadline.
    public func applyRevision(
        agentID: String,
        proposalId: String,
        proposal: SendProposal,
        results: [ProposalInstructionResult] = []
    ) throws {
        lock.lock()
        guard var entry = entries[proposalId] else {
            lock.unlock()
            throw ProposalRevisionApplyError.unknown
        }
        if entry.expired {
            lock.unlock()
            throw ProposalRevisionApplyError.expired
        }
        guard entry.agentID == agentID else {
            lock.unlock()
            throw ProposalRevisionApplyError.wrongAgent
        }
        guard entry.awaitingRevision,
              entry.decision == nil,
              entry.revisionKind == .reviseRequested || entry.revisionKind == .attentionRequested
        else {
            lock.unlock()
            throw ProposalRevisionApplyError.notWaitingForRevision
        }
        guard proposal.id == proposalId else {
            lock.unlock()
            throw ProposalRevisionApplyError.unknown
        }
        fingerprintIndex[entry.fingerprint] = nil
        let fp = Self.fingerprint(
            agentID: agentID,
            to: proposal.to,
            cc: proposal.cc,
            bcc: proposal.bcc,
            sender: proposal.sender,
            subject: proposal.subject,
            body: proposal.body
        )
        entry.fingerprint = fp
        entry.proposal = proposal
        entry.awaitingRevision = false
        entry.revisionKind = nil
        entry.pendingInterim = nil
        entry.agentPayload = nil
        entry.revisionResults = results
        fingerprintIndex[fp] = proposalId
        entries[proposalId] = entry
        let handler = revisionHandler
        lock.unlock()
        handler?(proposalId, proposal, results)
    }

    // MARK: - Private

    private func softTimeout(id: String, waiterID: UUID) {
        lock.lock()
        guard var entry = entries[id] else {
            lock.unlock()
            return
        }
        guard let idx = entry.waiters.firstIndex(where: { $0.id == waiterID }) else {
            lock.unlock()
            return
        }
        if entry.expired {
            let waiter = entry.waiters.remove(at: idx)
            entries[id] = entry
            lock.unlock()
            waiter.continuation.resume(returning: .expired)
            return
        }
        if let interim = entry.pendingInterim {
            entry.pendingInterim = nil
            let waiter = entry.waiters.remove(at: idx)
            entries[id] = entry
            lock.unlock()
            waiter.continuation.resume(returning: .decided(interim))
            return
        }
        if let decision = entry.decision {
            let waiter = entry.waiters.remove(at: idx)
            entries[id] = entry
            lock.unlock()
            waiter.continuation.resume(returning: .decided(decision))
            return
        }
        if entry.expiresAt <= now() {
            lock.unlock()
            expire(id: id)
            return
        }
        let waiter = entry.waiters.remove(at: idx)
        entries[id] = entry
        lock.unlock()
        waiter.continuation.resume(returning: .stillAwaiting)
    }

    private func expire(id: String) {
        lock.lock()
        guard var entry = entries[id], !entry.expired, entry.decision == nil else {
            lock.unlock()
            return
        }
        // Drop an in-flight confirm handoff so a late AppleScript completion cannot mark success.
        if entry.deliveryPhase == .inFlight {
            entry.deliveryPhase = .idle
        }
        entry.expired = true
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
                let ns = UInt64(delay * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
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
            let ns = UInt64(Self.terminalRetentionSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: ns)
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
            .map(\.proposalId)
        for id in stale {
            entries[id] = nil
            cancelExpiryTaskLocked(id: id)
        }
        lock.unlock()
    }
}
