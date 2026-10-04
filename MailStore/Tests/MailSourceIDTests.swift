import MailStore
import Testing

struct MailSourceIDTests {
    @Test func availableMatchesBuild() {
        #if DEBUG
        #expect(MailSourceID.includesFixture)
        #expect(MailSourceID.defaultSource == .fixture)
        #expect(MailSourceID.available(liveMailAccessible: false) == [.fixture])
        #expect(MailSourceID.available(liveMailAccessible: true) == [.fixture, .liveMail])
        #else
        #expect(!MailSourceID.includesFixture)
        #expect(MailSourceID.defaultSource == .liveMail)
        #expect(MailSourceID.available(liveMailAccessible: false) == [.liveMail])
        #expect(MailSourceID.available(liveMailAccessible: true) == [.liveMail])
        #endif
    }

    @Test func nextWalksAvailableThenWraps() {
        let both: [MailSourceID] = [.fixture, .liveMail]
        #expect(MailSourceID.fixture.next(in: both) == .liveMail)
        #expect(MailSourceID.liveMail.next(in: both) == .fixture)
    }

    @Test func nextWithOneSourceStays() {
        #expect(MailSourceID.fixture.next(in: [.fixture]) == .fixture)
        #expect(MailSourceID.liveMail.next(in: [.liveMail]) == .liveMail)
    }

    @Test func nextJumpsToFirstWhenCurrentUnavailable() {
        #expect(MailSourceID.liveMail.next(in: [.fixture]) == .fixture)
        #expect(MailSourceID.fixture.next(in: [.liveMail]) == .liveMail)
    }
}
