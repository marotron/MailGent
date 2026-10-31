import MailStore
import Testing

@Suite struct ProposeSendExpiryFormatTests {
    @Test func formatsHoursMinutesSeconds() {
        #expect(ProposeSendExpiryFormat.countdownLabel(remaining: 3_600) == "Expires in 1:00:00")
        #expect(ProposeSendExpiryFormat.countdownLabel(remaining: 3_661) == "Expires in 1:01:01")
        #expect(ProposeSendExpiryFormat.countdownLabel(remaining: 7_200) == "Expires in 2:00:00")
    }

    @Test func formatsMinutesSecondsUnderOneHour() {
        #expect(ProposeSendExpiryFormat.countdownLabel(remaining: 3_599) == "Expires in 59:59")
        #expect(ProposeSendExpiryFormat.countdownLabel(remaining: 90) == "Expires in 1:30")
        #expect(ProposeSendExpiryFormat.countdownLabel(remaining: 5) == "Expires in 0:05")
        #expect(ProposeSendExpiryFormat.countdownLabel(remaining: 0) == "Expires in 0:00")
    }

    @Test func clampsNegativeToZero() {
        #expect(ProposeSendExpiryFormat.countdownLabel(remaining: -3) == "Expires in 0:00")
    }
}
