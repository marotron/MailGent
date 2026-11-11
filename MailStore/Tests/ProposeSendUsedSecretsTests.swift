import Testing
@testable import MailStore

struct ProposeSendUsedSecretsTests {
    @Test func emptySpansYieldNoSummaries() {
        let body = "Call me on +44 111."
        #expect(ProposeSendUsedSecrets.summaries(body: body, spans: []).isEmpty)
    }

    @Test func orderedUniqueFromSpansInBodyOrder() {
        let body = "A secretA then secretB then secretA again."
        // Indices: secretA @ 2..<9, secretB @ 15..<22, secretA @ 28..<35
        let spans = [
            SecretConstantResolveSpan(name: "phone", start: 2, end: 9, updatedSinceDraft: false),
            SecretConstantResolveSpan(name: "pin", start: 15, end: 22, updatedSinceDraft: true),
            SecretConstantResolveSpan(name: "phone", start: 28, end: 35, updatedSinceDraft: false),
        ]
        let summaries = ProposeSendUsedSecrets.summaries(body: body, spans: spans)
        #expect(summaries.map(\.name) == ["phone", "pin"])
        #expect(summaries[0].value == "secretA")
        #expect(summaries[1].value == "secretB")
        #expect(summaries[1].updated == true)
        #expect(summaries[0].updated == false)
    }

    @Test func duplicateNameMergesUpdatedFlag() {
        let body = "xxOLDYYxxNEW"
        let spans = [
            SecretConstantResolveSpan(name: "code", start: 2, end: 5, updatedSinceDraft: false),
            SecretConstantResolveSpan(name: "code", start: 9, end: 12, updatedSinceDraft: true),
        ]
        let summaries = ProposeSendUsedSecrets.summaries(body: body, spans: spans)
        #expect(summaries.count == 1)
        #expect(summaries[0].name == "code")
        #expect(summaries[0].value == "OLD")
        #expect(summaries[0].updated == true)
    }

    @Test func missingNamesAreNotListedAsReplaced() {
        // Fail-closed path: unresolved tokens produce no spans (and no strip rows).
        let body = "Hi [[mg:missing]]"
        #expect(ProposeSendUsedSecrets.summaries(body: body, spans: []).isEmpty)
    }
}
