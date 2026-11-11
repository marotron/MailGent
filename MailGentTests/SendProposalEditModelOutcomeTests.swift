import MailStore
import Testing
@testable import MailGent

/// Terminal send strips passage refs; Look/Revise keep them. Enter default follows pin intent.
@MainActor
struct SendProposalEditModelOutcomeTests {
    private func makeProposal(body: String = "Hello one two.") -> SendProposal {
        SendProposal(
            agentName: "Cursor",
            to: ["sam@example.com"],
            subject: "Kickoff",
            body: body,
            sender: "marotron@gmail.com"
        )
    }

    private func rewriteInstruction(_ label: String = "make it shorter") -> ProposalPassageInstruction {
        ProposalPassageInstruction(id: "rewrite-make-it-shorter", kind: .rewrite, label: label)
    }

    @Test func sendPayloadStripsReferencesEvenWithPinsAndNotes() {
        let model = SendProposalEditModel(proposal: makeProposal(), constants: [], agentID: "agent")
        model.refer(quote: "Hello one")
        model.pins[0].note = "make it more natural"
        model.pins[0].instructions = [rewriteInstruction()]

        let payload = model.sendPayload()
        #expect(payload.outcome == "send")
        #expect(payload.references.isEmpty)
        #expect(!model.anchoredReferences().isEmpty, "live pins remain until Look/Revise")
    }

    @Test func attentionAndRevisePayloadsKeepAnchoredReferences() {
        let model = SendProposalEditModel(proposal: makeProposal(), constants: [], agentID: "agent")
        model.refer(quote: "Hello one")
        model.pins[0].note = "soften the ask"

        let attention = model.attentionPayload()
        #expect(attention.outcome == "attention_requested")
        #expect(attention.references.count == 1)
        #expect(attention.references[0].note == "soften the ask")

        let revise = model.revisePayload(presets: ["Shorter"], note: "trim the close")
        #expect(revise.outcome == "revise_requested")
        #expect(revise.references.count == 1)
        #expect(revise.references[0].note == "soften the ask")
    }

    @Test func preferAskToLookDefaultMatrix() {
        let model = SendProposalEditModel(proposal: makeProposal(), constants: [], agentID: "agent")
        #expect(!model.preferAskToLookDefault, "no pins")

        model.refer(quote: "Hello one")
        #expect(!model.preferAskToLookDefault, "pin alone is not passage intent")

        model.pins[0].note = "  "
        #expect(!model.preferAskToLookDefault, "whitespace-only note is not intent")

        model.pins[0].note = "soften"
        #expect(model.preferAskToLookDefault, "non-empty note prefers Look")

        model.pins[0].note = ""
        #expect(!model.preferAskToLookDefault)

        model.pins[0].instructions = [rewriteInstruction()]
        #expect(model.preferAskToLookDefault, "instruction chip prefers Look")
    }
}
