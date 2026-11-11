import Testing
@testable import MailStore

struct MailGentVersionTests {
    @Test func labelOmitsRcWhenCandidateIsZero() {
        #expect(MailGentVersion.label(marketing: "0.24.1", releaseCandidate: 0) == "0.24.1")
    }

    @Test func labelIncludesRcWhenCandidatePositive() {
        #expect(MailGentVersion.label(marketing: "0.24.1", releaseCandidate: 1) == "0.24.1-rc.1")
        #expect(MailGentVersion.label(marketing: "0.24.1", releaseCandidate: 2) == "0.24.1-rc.2")
    }

    @Test func currentConstantsMatchSemVerProgression() {
        #expect(MailGentVersion.marketing == "0.25.0")
        #expect(MailGentVersion.releaseCandidate == 0)
        #expect(MailGentVersion.label == "0.25.0")
        #expect(!MailGentVersion.isCandidate)
    }
}
