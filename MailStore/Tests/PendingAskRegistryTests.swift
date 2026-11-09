import Foundation
import Testing
@testable import MailStore

@Suite struct PendingAskRegistryTests {
    @Test func submitCreatesAskIdAndFutureExpiresAt() {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let registry = PendingAskRegistry(hardTimeoutSeconds: 3_600, now: clock.now, sleep: immediateSleep)
        let result = registry.submit(makeRequest())

        guard case let .created(id, expiresAt, fields) = result else {
            Issue.record("expected created")
            return
        }
        #expect(!id.isEmpty)
        #expect(expiresAt == Date(timeIntervalSince1970: 4_600))
        #expect(fields == ["Body"])
    }

    @Test func dedupeKeepsOriginalHardDeadline() {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let registry = PendingAskRegistry(hardTimeoutSeconds: 3_600, now: clock.now, sleep: immediateSleep)
        let first = registry.submit(makeRequest(messageID: "m1"))
        clock.instant = Date(timeIntervalSince1970: 1_100)
        let second = registry.submit(makeRequest(messageID: "m1"))

        guard case let .created(idA, expiresA, _) = first,
              case let .deduped(idB, expiresB, _) = second
        else {
            Issue.record("expected created then deduped")
            return
        }
        #expect(idA == idB)
        #expect(expiresA == expiresB)
        #expect(expiresA == Date(timeIntervalSince1970: 4_600))
    }

    @Test func identicalFingerprintWhilePendingReturnsSameAskId() {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        let a = registry.submit(makeRequest(messageID: "m1", fields: ["Body", "Attachments"]))
        let b = registry.submit(makeRequest(messageID: "m1", fields: ["Attachments", "Body"]))

        guard case let .created(idA, _, _) = a,
              case let .deduped(idB, _, _) = b
        else {
            Issue.record("expected dedupe")
            return
        }
        #expect(idA == idB)
    }

    @Test func differentFieldSetMessageFilenameOrAgentCreatesNewAsk() {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        guard case let .created(base, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }

        let fieldDiff = registry.submit(makeRequest(fields: ["Body", "Subject"]))
        let messageDiff = registry.submit(makeRequest(messageID: "other"))
        let agentDiff = registry.submit(makeRequest(agentID: "agent-2"))
        let filenameDiff = registry.submit(
            makeRequest(fields: ["Attachment content"], filename: "invoice.pdf")
        )
        let filenameOther = registry.submit(
            makeRequest(fields: ["Attachment content"], filename: "other.pdf")
        )

        guard case let .created(idFields, _, _) = fieldDiff,
              case let .created(idMessage, _, _) = messageDiff,
              case let .created(idAgent, _, _) = agentDiff,
              case let .created(idFileA, _, _) = filenameDiff,
              case let .created(idFileB, _, _) = filenameOther
        else {
            Issue.record("expected new asks")
            return
        }
        let ids = Set([base, idFields, idMessage, idAgent, idFileA, idFileB])
        #expect(ids.count == 6)
    }

    @Test func softAwaitReturnsStillAwaitingAndKeepsEntryPending() async {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        guard case let .created(id, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }

        let result = await registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 25)
        #expect(result == .stillAwaiting)
        #expect(registry.snapshot(askId: id)?.isPending == true)
    }

    @Test func resolveAllowAndBlockWakeWaiter() async {
        let registry = PendingAskRegistry(sleep: hangUntilCancelledSleep)
        guard case let .created(allowId, _, _) = registry.submit(makeRequest(messageID: "allow")) else {
            Issue.record("expected created")
            return
        }
        async let allowWait = registry.awaitDecision(askId: allowId, agentID: "agent-1", softTimeout: 60)
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(registry.resolve(askId: allowId, decision: .allow))
        #expect(await allowWait == .allow(fields: ["Body"]))

        guard case let .created(blockId, _, _) = registry.submit(makeRequest(messageID: "block")) else {
            Issue.record("expected created")
            return
        }
        async let blockWait = registry.awaitDecision(askId: blockId, agentID: "agent-1", softTimeout: 60)
        try? await Task.sleep(nanoseconds: 20_000_000)
        #expect(registry.resolve(askId: blockId, decision: .block))
        #expect(await blockWait == .block(fields: ["Body"]))
    }

    @Test func softTimeoutThenLateResolveSeesTerminalViaRetention() async {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        guard case let .created(id, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }
        #expect(await registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 1) == .stillAwaiting)
        #expect(registry.resolve(askId: id, decision: .allow))
        #expect(await registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 1) == .allow(fields: ["Body"]))
    }

    @Test func hardExpireWakesWaitersAndInvokesHandler() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let registry = PendingAskRegistry(hardTimeoutSeconds: 300, now: clock.now, sleep: hangUntilCancelledSleep)
        let box = ExpireBox()
        registry.setExpirationHandler { box.id = $0 }

        guard case let .created(id, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }
        async let wait = registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 60)
        try? await Task.sleep(nanoseconds: 20_000_000)
        clock.instant = Date(timeIntervalSince1970: 1_301)
        registry.expireIfNeeded()

        #expect(await wait == .expired)
        #expect(box.id == id)
        #expect(registry.isExpired(askId: id))
    }

    @Test func supersedeIsDistinctFromBlockAndExpired() async {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        guard case let .created(id, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.resolve(askId: id, decision: .superseded))
        let result = await registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 1)
        #expect(result == .superseded)
        #expect(result != .block(fields: ["Body"]))
        #expect(result != .expired)
    }

    @Test func noWaiterLeftDoesNotCancelAndHardExpiryStillRuns() {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let registry = PendingAskRegistry(hardTimeoutSeconds: 300, now: clock.now, sleep: immediateSleep)
        guard case let .created(id, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.snapshot(askId: id)?.isPending == true)
        clock.instant = Date(timeIntervalSince1970: 301)
        registry.expireIfNeeded()
        #expect(registry.isExpired(askId: id))
    }

    @Test func droppedSoftWaitContinuationDoesNotResolveOrCancel() async {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        guard case let .created(id, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }
        // Soft poll returns without deciding — same as a client that drops the HTTP await.
        #expect(await registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 1) == .stillAwaiting)
        #expect(registry.snapshot(askId: id)?.isPending == true)
        #expect(registry.resolve(askId: id, decision: .allow))
        #expect(await registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 1) == .allow(fields: ["Body"]))
    }

    @Test func wrongAgentOnAwaitAndClaimReturnsUnknownOrFalse() async {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        guard case let .created(id, _, _) = registry.submit(makeRequest(agentID: "agent-1")) else {
            Issue.record("expected created")
            return
        }
        #expect(await registry.awaitDecision(askId: id, agentID: "intruder", softTimeout: 1) == .unknown)
        #expect(registry.resolve(askId: id, decision: .allow))
        let claim = registry.claimLease(
            askId: id,
            agentID: "intruder",
            request: makeRequest(agentID: "intruder")
        )
        #expect(!claim)
        #expect(
            registry.claimLease(
                askId: id,
                agentID: "agent-1",
                request: makeRequest(agentID: "agent-1")
            )
        )
    }

    @Test func unknownAndPastRetentionReturnUnknown() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let registry = PendingAskRegistry(now: clock.now, sleep: immediateSleep)
        #expect(await registry.awaitDecision(askId: "missing", agentID: "agent-1", softTimeout: 1) == .unknown)

        guard case let .created(id, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.resolve(askId: id, decision: .block))
        clock.instant = Date(timeIntervalSince1970: PendingAskRegistry.terminalRetentionSeconds + 1)
        registry.expireIfNeeded()
        #expect(await registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 1) == .unknown)
    }

    @Test func leaseClaimSucceedsForExactFingerprintAfterAllow() {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        let request = makeRequest(fields: ["Body", "Attachments"], filename: nil)
        guard case let .created(id, _, _) = registry.submit(request) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.resolve(askId: id, decision: .allow))
        #expect(registry.claimLease(askId: id, agentID: "agent-1", request: request))
    }

    @Test func leaseClaimIsIdempotentWithinRetention() {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        let request = makeRequest()
        guard case let .created(id, _, _) = registry.submit(request) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.resolve(askId: id, decision: .allow))
        #expect(registry.claimLease(askId: id, agentID: "agent-1", request: request))
        #expect(registry.claimLease(askId: id, agentID: "agent-1", request: request))
    }

    @Test func leaseRejectsDifferentMessageFieldsAgentOrAskId() {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        let request = makeRequest(messageID: "m1", fields: ["Body"])
        guard case let .created(id, _, _) = registry.submit(request) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.resolve(askId: id, decision: .allow))

        #expect(!registry.claimLease(
            askId: id,
            agentID: "agent-1",
            request: makeRequest(messageID: "m2", fields: ["Body"])
        ))
        #expect(!registry.claimLease(
            askId: id,
            agentID: "agent-1",
            request: makeRequest(messageID: "m1", fields: ["Subject"])
        ))
        #expect(!registry.claimLease(
            askId: id,
            agentID: "agent-2",
            request: makeRequest(agentID: "agent-2", messageID: "m1", fields: ["Body"])
        ))
        #expect(!registry.claimLease(
            askId: "other",
            agentID: "agent-1",
            request: request
        ))
    }

    @Test func softClampAndCapByRemainingHardAndDefaultIs25() {
        #expect(PendingAskRegistry.defaultSoftTimeoutSeconds == 25)
        #expect(PendingAskRegistry.clampSoftTimeout(0) == 1)
        #expect(PendingAskRegistry.clampSoftTimeout(25) == 25)
        #expect(PendingAskRegistry.clampSoftTimeout(999) == 120)

        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let slept = SleepProbe()
        let registry = PendingAskRegistry(hardTimeoutSeconds: 300, now: clock.now, sleep: slept.sleep)
        guard case let .created(id, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }
        clock.instant = Date(timeIntervalSince1970: 290)
        let task = Task {
            await registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 60)
        }
        // Allow enqueue + sleep scheduling.
        let deadline = Date().addingTimeInterval(1)
        while slept.lastSeconds == nil, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        task.cancel()
        #expect(slept.lastSeconds == 10)
    }

    @Test func advancingInjectedClockExpiresWithoutWallSleep() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let registry = PendingAskRegistry(hardTimeoutSeconds: 300, now: clock.now, sleep: immediateSleep)
        guard case let .created(id, _, _) = registry.submit(makeRequest()) else {
            Issue.record("expected created")
            return
        }
        clock.instant = Date(timeIntervalSince1970: 1_300)
        registry.expireIfNeeded()
        #expect(await registry.awaitDecision(askId: id, agentID: "agent-1", softTimeout: 1) == .expired)
    }

    @Test func supersedeMatchingWakesPendingAsks() {
        let registry = PendingAskRegistry(sleep: immediateSleep)
        guard case let .created(id, _, _) = registry.submit(makeRequest(messageID: "m1")) else {
            Issue.record("expected created")
            return
        }
        let ids = registry.supersedeMatching { $0.pendingFields.contains("Body") }
        #expect(ids == [id])
        #expect(registry.snapshot(askId: id)?.isPending == false)
    }
}

// MARK: - Fixtures

private final class FakeClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _instant: Date

    var instant: Date {
        get { lock.lock(); defer { lock.unlock() }; return _instant }
        set { lock.lock(); _instant = newValue; lock.unlock() }
    }

    init(_ instant: Date) { _instant = instant }

    var now: @Sendable () -> Date {
        { [self] in self.instant }
    }
}

private final class ExpireBox: @unchecked Sendable {
    var id: String?
}

private final class SleepProbe: @unchecked Sendable {
    nonisolated(unsafe) var lastSeconds: TimeInterval?

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in
            let seconds = Double(duration.components.seconds)
                + Double(duration.components.attoseconds) / 1e18
            self.lastSeconds = seconds
            try await Task.sleep(nanoseconds: 60_000_000_000)
        }
    }
}

private let immediateSleep: @Sendable (Duration) async throws -> Void = { _ in }

private let hangUntilCancelledSleep: @Sendable (Duration) async throws -> Void = { _ in
    try await Task.sleep(nanoseconds: 60_000_000_000)
}

private func makeRequest(
    agentID: String = "agent-1",
    accountID: String = "acct",
    placement: String = "INBOX",
    messageID: String = "m1",
    fields: [String] = ["Body"],
    filename: String? = nil
) -> PendingAskRequest {
    PendingAskRequest(
        agentID: agentID,
        accountID: accountID,
        placement: placement,
        messageID: messageID,
        fields: fields,
        filename: filename
    )
}
