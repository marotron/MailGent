import Testing
import MailStore
@testable import MailGent

struct ConditionalAccessAskRuleDraftTests {
    @Test func defaultFieldsKeepsAttachmentContentWhenNamesWereNotAsked() {
        let fields = ConditionalAccessAskRuleDraft.defaultFields(
            for: ["Body", "Attachment content"],
            polarity: .pass
        )

        #expect(fields.bodyMode == .on)
        #expect(fields.attachmentMetadataMode == .on)
        #expect(fields.attachmentContentMode == .on)
        #expect(fields.subjectMode == .off)
    }

    @Test func defaultFieldsBlockAlsoCarriesNamesWithContent() {
        let fields = ConditionalAccessAskRuleDraft.defaultFields(
            for: ["Body", "Attachment content"],
            polarity: .block
        )

        #expect(fields.bodyMode == .on)
        #expect(fields.attachmentMetadataMode == .on)
        #expect(fields.attachmentContentMode == .on)
    }

    @Test func enableScopeMapsMailboxAndAccountWide() {
        #expect(AskRuleEnableScope.thisMailbox.placement(forAskPlacement: "INBOX") == "INBOX")
        #expect(AskRuleEnableScope.thisAccount.placement(forAskPlacement: "INBOX") == nil)
    }
}
