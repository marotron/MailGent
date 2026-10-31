import Foundation
import Testing
@testable import MailStore

@Suite struct PendingProposalRegistryTests {
    @Test func submitCreatesAwaitingProposal() {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let registry = PendingProposalRegistry(hardTimeoutSeconds: 3_600, now: clock.now)
        let proposal = makeProposal()

        let result = registry.submit(agentID: "agent-1", proposal: proposal)

        guard case let .created(id, expiresAt, stored) = result else {
            Issue.record("expected created")
            return
        }
        #expect(id == proposal.id)
        #expect(stored.id == proposal.id)
        #expect(expiresAt == Date(timeIntervalSince1970: 4_600))
    }

    @Test func fingerprintHitReturnsSameIdWithoutSecondCreate() {
        let registry = PendingProposalRegistry(hardTimeoutSeconds: 3_600)
        let first = makeProposal(id: "p1", subject: "Hi", body: "Hello")
        let second = makeProposal(id: "p2", subject: "Hi", body: "Hello")

        let a = registry.submit(agentID: "agent-1", proposal: first)
        let b = registry.submit(agentID: "agent-1", proposal: second)

        guard case let .created(idA, _, _) = a else {
            Issue.record("expected created")
            return
        }
        guard case let .deduped(idB, _, _) = b else {
            Issue.record("expected deduped")
            return
        }
        #expect(idA == idB)
        #expect(idA == "p1")
    }

    @Test func fingerprintIgnoresContext() {
        let registry = PendingProposalRegistry()
        let withContext = makeProposal(id: "a")
        // Context is not on SendProposal factory here — fingerprint API ignores it by construction.
        let again = makeProposal(id: "b", subject: withContext.subject, body: withContext.body)
        let a = registry.submit(agentID: "agent-1", proposal: withContext)
        let b = registry.submit(agentID: "agent-1", proposal: again)
        guard case let .created(id, _, _) = a,
              case let .deduped(same, _, _) = b
        else {
            Issue.record("expected dedupe")
            return
        }
        #expect(id == same)
    }

    @Test func softWaitTimesOutWhileStillAwaiting() async {
        let registry = PendingProposalRegistry(hardTimeoutSeconds: 3_600)
        let proposal = makeProposal()
        guard case let .created(id, _, _) = registry.submit(agentID: "agent-1", proposal: proposal) else {
            Issue.record("expected created")
            return
        }

        let result = await registry.awaitDecision(id: id, softTimeout: 1)
        #expect(result == .stillAwaiting)
    }

    @Test func resolveWakesAwaiterWithDecision() async {
        let registry = PendingProposalRegistry(hardTimeoutSeconds: 3_600)
        let proposal = makeProposal()
        guard case let .created(id, _, _) = registry.submit(agentID: "agent-1", proposal: proposal) else {
            Issue.record("expected created")
            return
        }

        async let wait = registry.awaitDecision(id: id, softTimeout: 60)
        try? await Task.sleep(nanoseconds: 50_000_000)
        #expect(registry.resolve(id: id, decision: .send))
        let result = await wait
        #expect(result == .decided(.send))
    }

    @Test func secondResolveIsNoOp() {
        let registry = PendingProposalRegistry()
        let proposal = makeProposal()
        guard case let .created(id, _, _) = registry.submit(agentID: "agent-1", proposal: proposal) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.resolve(id: id, decision: .send))
        #expect(!registry.resolve(id: id, decision: .cancel))
    }

    @Test func hardClockExpiresWithoutDeliverDecision() async {
        let clock = FakeClock(Date(timeIntervalSince1970: 1_000))
        let registry = PendingProposalRegistry(hardTimeoutSeconds: 300, now: clock.now)
        let proposal = makeProposal()
        guard case let .created(id, _, _) = registry.submit(agentID: "agent-1", proposal: proposal) else {
            Issue.record("expected created")
            return
        }

        clock.instant = Date(timeIntervalSince1970: 1_301)
        registry.expireIfNeeded()

        let result = await registry.awaitDecision(id: id, softTimeout: 1)
        #expect(result == .expired)
        #expect(!registry.resolve(id: id, decision: .send))
    }

    @Test func lateAwaitAfterTerminalStillReturnsOutcome() async {
        let registry = PendingProposalRegistry()
        let proposal = makeProposal()
        guard case let .created(id, _, _) = registry.submit(agentID: "agent-1", proposal: proposal) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.resolve(id: id, decision: .cancel))
        let result = await registry.awaitDecision(id: id, softTimeout: 1)
        #expect(result == .decided(.cancel))
    }

    @Test func unknownIdReturnsUnknown() async {
        let registry = PendingProposalRegistry()
        let result = await registry.awaitDecision(id: "missing", softTimeout: 1)
        #expect(result == .unknown)
    }

    @Test func hardTimeoutClampedFromSettingsSeconds() {
        let registry = PendingProposalRegistry(hardTimeoutSeconds: 10)
        #expect(registry.readHardTimeoutSeconds() == 300)

        registry.setHardTimeoutSeconds(99_999)
        #expect(registry.readHardTimeoutSeconds() == 28_800)

        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let mid = PendingProposalRegistry(hardTimeoutSeconds: 1_800, now: clock.now)
        let proposal = makeProposal()
        guard case let .created(_, expiresAt, _) = mid.submit(agentID: "a", proposal: proposal) else {
            Issue.record("expected created")
            return
        }
        #expect(expiresAt == Date(timeIntervalSince1970: 1_800))
    }

    @Test func expirationHandlerFiresOnHardExpire() {
        let clock = FakeClock(Date(timeIntervalSince1970: 0))
        let registry = PendingProposalRegistry(hardTimeoutSeconds: 300, now: clock.now)
        let box = ExpireBox()
        registry.setExpirationHandler { id in box.id = id }
        let proposal = makeProposal(id: "exp-1")
        _ = registry.submit(agentID: "a", proposal: proposal)
        clock.instant = Date(timeIntervalSince1970: 301)
        registry.expireIfNeeded()
        #expect(box.id == "exp-1")
    }

    @Test func releaseDeliveryClaimAllowsSecondClaim() {
        let registry = PendingProposalRegistry()
        let proposal = makeProposal()
        guard case let .created(id, _, _) = registry.submit(agentID: "agent-1", proposal: proposal) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.resolve(id: id, decision: .send))
        #expect(registry.claimDelivery(id: id))
        #expect(!registry.claimDelivery(id: id))
        #expect(!registry.isDeliverySucceeded(id: id))

        registry.releaseDeliveryClaim(id: id)
        #expect(registry.claimDelivery(id: id))
        registry.markDeliverySucceeded(id: id)
        #expect(registry.isDeliverySucceeded(id: id))
        #expect(!registry.claimDelivery(id: id))
    }

    @Test func claimDeliveryAllowedBeforeDecisionForConfirmHandoff() {
        let registry = PendingProposalRegistry()
        let proposal = makeProposal()
        guard case let .created(id, _, _) = registry.submit(agentID: "agent-1", proposal: proposal) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.claimDelivery(id: id))
        registry.markDeliverySucceeded(id: id)
        #expect(registry.resolve(id: id, decision: .send))
        #expect(registry.isDeliverySucceeded(id: id))
        #expect(!registry.claimDelivery(id: id))
    }

    @Test func claimDeliveryAllowedAfterCancelForAwaitPath() {
        let registry = PendingProposalRegistry()
        let proposal = makeProposal()
        guard case let .created(id, _, _) = registry.submit(agentID: "agent-1", proposal: proposal) else {
            Issue.record("expected created")
            return
        }
        #expect(registry.resolve(id: id, decision: .cancel))
        #expect(registry.claimDelivery(id: id))
        registry.markDeliverySucceeded(id: id)
        #expect(registry.isDeliverySucceeded(id: id))
    }
}

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

private func makeProposal(
    id: String = UUID().uuidString,
    subject: String = "Hi",
    body: String = "Hello",
    to: [String] = ["alex@example.com"]
) -> SendProposal {
    SendProposal(
        id: id,
        agentName: "Cursor",
        to: to,
        subject: subject,
        body: body
    )
}
