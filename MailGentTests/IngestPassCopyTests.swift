import Testing
@testable import MailGent

struct IngestPassCopyTests {
    @Test func summaryShowsNewAndRemovedTogether() {
        #expect(IngestPassCopy.summary(newCount: 44, removedCount: 2277) == "+44 −2277 → −2233")
        #expect(IngestPassCopy.summary(newCount: 0, removedCount: 2277) == "−2277")
        #expect(IngestPassCopy.summary(newCount: 44, removedCount: 0) == "+44")
        #expect(IngestPassCopy.summary(newCount: 0, removedCount: 0) == "0")
        #expect(IngestPassCopy.summary(newCount: 10, removedCount: 10) == "+10 −10 → 0")
        #expect(IngestPassCopy.signed(-2233) == "−2233")
        #expect(IngestPassCopy.signed(44) == "+44")
        #expect(
            String(IngestPassCopy.attributedSummary(newCount: 44, removedCount: 2277).characters)
                == "+44 −2277 → −2233"
        )
    }
}
