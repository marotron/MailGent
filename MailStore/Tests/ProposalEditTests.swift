import Foundation
import Testing
@testable import MailStore

@Suite struct ProposalEditTests {
    private func phone() -> SecretConstant {
        SecretConstant(
            name: "phone_mobile",
            label: "Mobile",
            hint: .phone,
            value: "+1 555 0142",
            allowedAgentIDs: ["cursor"]
        )
    }

    private func home() -> SecretConstant {
        SecretConstant(
            name: "home_address",
            label: "Home",
            hint: .address,
            value: "1 Secret Lane",
            allowedAgentIDs: []
        )
    }

    @Test func wordDiffMergesAShortGapAndKeepsASentenceBreak() {
        let swapped = ProposalBodyDiff.hunks(
            before: "Thursday 2pm works",
            after: "Friday 10am works better"
        )
        #expect(swapped == [ProposalTextHunk(before: "Thursday 2pm works", after: "Friday 10am works better")])

        let split = ProposalBodyDiff.hunks(
            before: "Hello world. Goodbye",
            after: "Hello there. Goodbye"
        )
        #expect(split == [ProposalTextHunk(before: "world.", after: "there.")])
    }

    @Test func recipientDiffIsFullListBeforeAndAfter() {
        let swap = ProposalEnvelopeDiff.swap(
            before: ["Joanna Chen <joanna@acme.example>"],
            after: ["Joanna Chen <joanna@acme.example>", "Sam <sam@x.example>"],
            redact: { $0 }
        )
        #expect(
            swap == ProposalFieldSwap(
                before: "Joanna Chen <joanna@acme.example>",
                after: "Joanna Chen <joanna@acme.example>, Sam <sam@x.example>"
            )
        )
        #expect(
            ProposalEnvelopeDiff.added(
                before: ["Joanna Chen <joanna@acme.example>"],
                after: ["Joanna Chen <joanna@acme.example>", "Sam <sam@x.example>"]
            ) == ["Sam <sam@x.example>"]
        )
    }

    @Test func bodyLiteralBecomesTokenAndEnvelopeLiteralIsOnlyRedacted() {
        let constants = [phone(), home()]
        let body = ProposalBodyTokens.literalsToTokens(
            "Call me on +1 555 0142 today",
            constants: constants,
            agentID: "cursor"
        )
        #expect(body == "Call me on {{mg:phone_mobile}} today")

        let changes = ProposalPayloadBuilder.changes(
            beforeTo: ["Jo <jo@acme.example>"],
            afterTo: ["Jo <jo@acme.example>"],
            beforeCc: [],
            afterCc: [],
            beforeBcc: [],
            afterBcc: [],
            beforeSubject: "Hello",
            afterSubject: "Meet at +1 555 0142",
            beforeBody: "Hello +1 555 0142",
            afterBody: "Hello {{mg:phone_mobile}}",
            constants: constants,
            agentID: "cursor"
        )
        #expect(changes.to == nil)
        #expect(changes.subject == ProposalFieldSwap(before: "Hello", after: "Meet at [redacted:phone_mobile]"))
        #expect(changes.body == [
            ProposalTextHunk(before: "[redacted:phone_mobile]", after: "{{mg:phone_mobile}}")
        ])
        let redactedHome = ProposalRedaction.redact("Ship to 1 Secret Lane", constants: constants, agentID: "cursor")
        #expect(redactedHome == "Ship to [redacted]")
        #expect(!redactedHome.contains("1 Secret Lane"))
    }

    @Test func selectionSnapAndQuoteKeepTheToken() {
        let text = "Reach me at {{mg:phone_mobile}} tomorrow"
        let token = "{{mg:phone_mobile}}"
        let tokenStart = text.distance(from: text.startIndex, to: text.range(of: token)!.lowerBound)
        let inside = tokenStart + 4
        let snapped = ProposalBodyTokens.snap(in: text, start: inside, end: inside + 3)
        #expect(snapped.start == tokenStart)
        #expect(snapped.end == tokenStart + token.count)
        let quote = ProposalBodyTokens.substring(text, start: snapped.start, end: snapped.end)
        #expect(quote == "{{mg:phone_mobile}}")

        let shown = "I'd like you at +1 555 0142 tomorrow"
        let tokenized = ProposalBodyTokens.literalsToTokens(shown, constants: [phone()], agentID: "cursor")
        let agent = ProposalRedaction.redact(tokenized, constants: [phone(), home()], agentID: "cursor")
        #expect(agent == "I'd like you at {{mg:phone_mobile}} tomorrow")
        #expect(!agent.contains("+1 555 0142"))
    }

    @Test func missingPassageIsStaleAndQuoteStaysTokenized() {
        let pins = [
            ProposalPin(id: "r1", quote: "call {{mg:phone_mobile}}", note: "check +1 555 0142"),
            ProposalPin(id: "r2", quote: "gone passage", note: "")
        ]
        let refs = ProposalPins.anchor(pins, in: "Please call {{mg:phone_mobile}} soon") { text in
            ProposalRedaction.redact(text, constants: [phone()], agentID: "cursor")
        }
        #expect(refs[0].stale == false)
        #expect(refs[0].quote == "call {{mg:phone_mobile}}")
        #expect(refs[0].note == "check [redacted:phone_mobile]")
        #expect(refs[0].instructionText.isEmpty)
        #expect(refs[0].dictionary()["instructionText"] == nil)
        #expect(!((refs[0].note ?? "").contains("+1 555 0142")))
        #expect(refs[1].stale == true)
    }

    @Test func noteOnlyReferenceOmitsInstructionText() {
        let pin = ProposalPin(
            id: "r1",
            quote: "ale bardzo dobrze wspominam nasze rozmowy",
            note: "to powinno byc odnosnie rozmowy z patrycja"
        )
        let reference = ProposalPins.anchor([pin], in: pin.quote) { $0 }[0]
        let dictionary = reference.dictionary()

        #expect(reference.note == pin.note)
        #expect(reference.instructionText.isEmpty)
        #expect(dictionary["note"] as? String == pin.note)
        #expect(dictionary["instructionText"] == nil)
        #expect(dictionary["instructions"] == nil)
    }

    @Test func passageInstructionsAreStructuredAndHaveARedactedTextFallback() {
        let pin = ProposalPin(
            id: "r1",
            quote: "Thursday works",
            note: "Confirm with +1 555 0142",
            instructions: [
                ProposalPassageInstruction(
                    id: "accurate",
                    kind: .ask,
                    label: "Check +1 555 0142 is accurate",
                    answerShape: .yesNo
                ),
                ProposalPassageInstruction(
                    id: "formal",
                    kind: .rewrite,
                    label: "Rewrite more formally"
                ),
            ]
        )

        let reference = ProposalPins.anchor([pin], in: pin.quote) {
            ProposalRedaction.redact($0, constants: [phone()], agentID: "cursor")
        }[0]
        let dictionary = reference.dictionary()
        let instructions = dictionary["instructions"] as? [[String: Any]]

        #expect(instructions?.count == 2)
        #expect(instructions?[0]["id"] as? String == "accurate")
        #expect(instructions?[0]["kind"] as? String == "ask")
        #expect((instructions?[0]["answerShape"] as? [String: Any])?["type"] as? String == "yes_no")
        #expect(instructions?[1]["kind"] as? String == "rewrite")
        #expect(reference.note == "Confirm with [redacted:phone_mobile]")
        #expect(
            reference.instructionText
                == "Ask: Check [redacted:phone_mobile] is accurate (answer: yes/no). Rewrite: Rewrite more formally."
        )
        #expect(!reference.instructionText.contains("Note:"))
        #expect(!reference.instructionText.contains("+1 555 0142"))
        #expect(dictionary["instructionText"] as? String == reference.instructionText)
    }

    @Test func revisionResultsValidateTypedAnswersAgainstTheDeclaredShape() throws {
        let references = [
            ProposalReferenceRecord(
                id: "r1",
                quote: "Thursday works",
                note: nil,
                stale: false,
                instructions: [
                    ProposalPassageInstruction(
                        id: "accurate",
                        kind: .ask,
                        label: "Check this is accurate",
                        answerShape: .yesNo
                    ),
                    ProposalPassageInstruction(
                        id: "formal",
                        kind: .rewrite,
                        label: "Rewrite more formally"
                    ),
                ]
            ),
        ]
        let results = try ProposalInstructionResult.parseList(
            [
                [
                    "referenceId": "r1",
                    "instructionId": "accurate",
                    "status": "pass",
                    "answer": ["type": "yes_no", "value": true],
                ],
                [
                    "referenceId": "r1",
                    "instructionId": "formal",
                    "status": "pass",
                ],
            ],
            references: references
        )

        #expect(results == [
            ProposalInstructionResult(
                referenceID: "r1",
                instructionID: "accurate",
                status: .pass,
                answer: .yesNo(true)
            ),
            ProposalInstructionResult(
                referenceID: "r1",
                instructionID: "formal",
                status: .pass
            ),
        ])
        #expect(throws: ProposalInstructionResultError.answerShapeMismatch) {
            try ProposalInstructionResult.parseList(
                [[
                    "referenceId": "r1",
                    "instructionId": "accurate",
                    "answer": ["type": "text", "value": "yes"],
                ]],
                references: references
            )
        }
    }

    @Test func fuzzyRankPrefersTheCloserPreset() {
        let presets = ProposalNoteFuzzy.defaultPresets
        let ranked = ProposalNoteFuzzy.suggestions(query: "shorter", presets: presets)
        #expect(ranked.first == "Make this shorter")
        #expect(!ranked.contains("Rewrite more formally"))
        let all = ProposalNoteFuzzy.suggestions(query: "", presets: presets)
        #expect(all == presets)
    }

    @Test func reviseInstructionJoinsPresetNoteAndEdits() {
        let edits = ProposalChanges(
            body: [ProposalTextHunk(before: "Thursday 2pm works", after: "Friday 10am works better")]
        )
        let payload = ProposalPayloadBuilder.revise(
            proposalId: "p_8f2c",
            presets: ["Warmer"],
            note: "keep the Thursday time",
            currentBody: "Hi {{mg:phone_mobile}}",
            userEdits: edits,
            references: [],
            context: nil,
            constants: [phone()],
            agentID: "cursor"
        )
        #expect(payload.outcome == "revise_requested")
        #expect(
            payload.revision?.instructionText
                == "Regenerate the whole draft. Make it warmer. Note from the user: keep the Thursday time. The user also edited the draft by hand (userEdits). Keep those edits unless they conflict with the note."
        )
        #expect(payload.userEdits == edits)
        #expect(payload.currentBody == "Hi {{mg:phone_mobile}}")
        #expect(payload.message == ProposalAgentPayload.reviseNextStepMessage)
        let json = payload.dictionary()
        #expect(json["outcome"] as? String == "revise_requested")
        #expect(json["message"] as? String == ProposalAgentPayload.reviseNextStepMessage)
        let revision = json["revision"] as? [String: Any]
        #expect((revision?["scope"] as? [String: Any])?["type"] as? String == "draft")
    }

    @Test func attentionPayloadIncludesReviseNextStepMessage() {
        let payload = ProposalPayloadBuilder.attention(
            proposalId: "p_look",
            userEdits: ProposalChanges(),
            references: [],
            context: nil
        )
        #expect(payload.outcome == "attention_requested")
        #expect(payload.message == ProposalAgentPayload.reviseNextStepMessage)
        #expect(payload.dictionary()["message"] as? String == ProposalAgentPayload.reviseNextStepMessage)
    }

    @Test func uneditedSendOmitsChanges() {
        let payload = ProposalPayloadBuilder.send(
            proposalId: "p1",
            changes: ProposalChanges(),
            sentBody: nil,
            references: [],
            context: nil
        )
        #expect(payload.edited == false)
        #expect(payload.dictionary()["changes"] == nil)
        #expect(payload.dictionary()["sentBody"] == nil)
    }
}
