import Foundation
import Testing
@testable import MailGent

struct MenuBarIconPulseTests {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func idleUntilRecorded() {
        #expect(MenuBarIconPulse().kind(at: t0) == .idle)
    }

    @Test func successHoldsThenReturnsIdle() {
        var pulse = MenuBarIconPulse()
        pulse.recordSuccess(at: t0)
        #expect(pulse.kind(at: t0.addingTimeInterval(1)) == .success)
        #expect(pulse.kind(at: t0.addingTimeInterval(MenuBarIconPulse.successHold - 0.01)) == .success)
        #expect(pulse.kind(at: t0.addingTimeInterval(MenuBarIconPulse.successHold)) == .idle)
    }

    @Test func errorHoldsLongerThanSuccess() {
        var pulse = MenuBarIconPulse()
        pulse.recordError(at: t0)
        #expect(
            pulse.kind(at: t0.addingTimeInterval(MenuBarIconPulse.successHold + 0.1)) == .error
        )
        #expect(pulse.kind(at: t0.addingTimeInterval(MenuBarIconPulse.errorHold)) == .idle)
    }

    @Test func laterOutcomeReplacesEarlierPulse() {
        var pulse = MenuBarIconPulse()
        pulse.recordSuccess(at: t0)
        pulse.recordError(at: t0.addingTimeInterval(0.2))
        #expect(pulse.kind(at: t0.addingTimeInterval(0.3)) == .error)
    }

    @Test func clearReturnsIdleImmediately() {
        var pulse = MenuBarIconPulse()
        pulse.recordError(at: t0)
        pulse.clear()
        #expect(pulse.kind(at: t0) == .idle)
    }
}
