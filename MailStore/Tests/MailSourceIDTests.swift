import MailStore
import Testing

struct MailSourceIDTests {
    @Test func availableOmitsLiveMailWhenInaccessible() {
        #expect(MailSourceID.available(liveMailAccessible: false) == [.fixture])
        #expect(MailSourceID.available(liveMailAccessible: true) == [.fixture, .liveMail])
    }

    @Test func nextWalksAvailableThenWraps() {
        let both: [MailSourceID] = [.fixture, .liveMail]
        #expect(MailSourceID.fixture.next(in: both) == .liveMail)
        #expect(MailSourceID.liveMail.next(in: both) == .fixture)
    }

    @Test func nextWithOneSourceStays() {
        #expect(MailSourceID.fixture.next(in: [.fixture]) == .fixture)
    }

    @Test func nextJumpsToFirstWhenCurrentUnavailable() {
        #expect(MailSourceID.liveMail.next(in: [.fixture]) == .fixture)
    }
}
