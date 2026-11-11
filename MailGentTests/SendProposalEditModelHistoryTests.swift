import MailStore
import Testing
@testable import MailGent

/// Draft version history in the experimental edit dialog: every agent revision
/// appends a version, the stepper previews past versions read-only, and each
/// version reports its change count against the previous one.
@MainActor
struct SendProposalEditModelHistoryTests {
    private func makeProposal(body: String, subject: String = "Kickoff") -> SendProposal {
        SendProposal(
            agentName: "Cursor",
            to: ["sam@example.com"],
            subject: subject,
            body: body,
            sender: "marotron@gmail.com"
        )
    }

    @Test func initialSecretLiteralNormalizationIsNotReportedAsAHumanEdit() {
        let phone = SecretConstant(
            name: "phone",
            label: "Mobile",
            value: "+44 7501 222825",
            allowedAgentIDs: ["agent"]
        )
        let model = SendProposalEditModel(
            proposal: makeProposal(body: "Call me on +44 7501 222825."),
            constants: [phone],
            agentID: "agent"
        )

        #expect(model.tokenizedBody == "Call me on {{mg:phone}}.")
        #expect(model.changes.isEmpty)
    }

    @Test func agentRevisionAppendsAVersionAndJumpsToLatest() {
        let model = SendProposalEditModel(proposal: makeProposal(body: "Hello one two."), constants: [], agentID: "agent")
        #expect(model.versions.count == 1)
        #expect(model.versions[0].origin == "Agent proposal")

        model.applyAgentDraft(
            makeProposal(body: "Hello three two."),
            roundTrips: 1,
            resolved: nil
        )
        #expect(model.versions.count == 2)
        #expect(model.versions[1].origin == "Agent revision")
        #expect(model.tokenizedBody == "Hello three two.")
        #expect(model.viewedVersion == nil, "a new revision must return the view to the latest draft")
    }

    @Test func focusingARowDoesNotExpandItAndChangesCanBeHiddenIndependently() {
        let model = SendProposalEditModel(proposal: makeProposal(body: "Hello one two."), constants: [], agentID: "agent")
        model.refer(quote: "Hello one")

        model.focusReference("r1")
        #expect(model.selectedReferenceID == "r1")
        #expect(model.expandedReferenceID == nil)

        model.toggleReferenceExpansion("r1")
        #expect(model.expandedReferenceID == "r1")
        model.focusReference("r1")
        #expect(model.expandedReferenceID == "r1", "focusing the passage must not change expansion")

        #expect(model.changesVisible)
        model.toggleChangesVisibility()
        #expect(!model.changesVisible)
        #expect(model.selectedReferenceID == "r1")
    }

    @Test func stepperPreviewsPastVersionAndReturnsToCurrent() {
        let model = SendProposalEditModel(proposal: makeProposal(body: "Hello one two."), constants: [], agentID: "agent")
        model.applyAgentDraft(makeProposal(body: "Hello three two."), roundTrips: 1, resolved: nil)

        #expect(model.canStepBack)
        model.stepBack()
        #expect(model.viewedVersion?.id == 1)
        #expect(model.viewedVersion?.tokenizedBody == "Hello one two.")
        #expect(model.viewingPast)

        #expect(model.canStepForward)
        model.stepForward()
        #expect(model.viewedVersion == nil)
        #expect(!model.canStepForward)
        #expect(!model.canStepBack == false)
    }

    @Test func sendAndOpenInMailUseTheBrowsedDraftVersion() {
        let model = SendProposalEditModel(
            proposal: makeProposal(body: "Hello one two.", subject: "Kickoff"),
            constants: [],
            agentID: "agent"
        )
        model.applyAgentDraft(
            makeProposal(body: "Hello three two.", subject: "Kickoff!"),
            roundTrips: 1,
            resolved: nil
        )
        #expect(model.deliveredProposal().body == "Hello three two.")
        #expect(model.deliveredProposal().subject == "Kickoff!")

        model.stepBack()
        let past = model.deliveredProposal()
        #expect(past.body == "Hello one two.")
        #expect(past.subject == "Kickoff")
        #expect(past.tokenizedBody == "Hello one two.")

        let payload = model.sendPayload()
        #expect(payload.edited == true)
        #expect(payload.sentBody == "Hello one two.")

        model.stepForward()
        #expect(model.deliveredProposal().body == "Hello three two.")
        #expect(model.deliveredProposal().subject == "Kickoff!")
    }

    @Test func usedSecretStripFollowsBrowsedDraftVersion() {
        let phone = SecretConstant(
            name: "phone",
            label: "Mobile",
            value: "+44 111",
            allowedAgentIDs: ["agent"]
        )
        let model = SendProposalEditModel(
            proposal: makeProposal(body: "Call {{mg:phone}}."),
            constants: [phone],
            agentID: "agent"
        )
        model.applyAgentDraft(
            makeProposal(body: "No secrets here."),
            roundTrips: 1,
            resolved: nil
        )

        let latest = model.deliveredProposal()
        #expect(
            ProposeSendUsedSecrets.summaries(
                body: latest.body,
                spans: latest.secretConstantSpans
            ).isEmpty
        )

        model.stepBack()
        let past = model.deliveredProposal()
        let strip = ProposeSendUsedSecrets.summaries(
            body: past.body,
            spans: past.secretConstantSpans
        )
        #expect(strip.map(\.name) == ["phone"])
        #expect(strip.first?.value == "+44 111")
    }

    @Test func missingSecretYieldsNoReplacedStripRows() {
        let model = SendProposalEditModel(
            proposal: makeProposal(body: "Call {{mg:missing}}."),
            constants: [],
            agentID: "agent"
        )
        let delivered = model.deliveredProposal()
        #expect(!delivered.secretConstantMissing.isEmpty)
        #expect(
            ProposeSendUsedSecrets.summaries(
                body: delivered.body,
                spans: delivered.secretConstantSpans
            ).isEmpty
        )
    }

    @Test func versionChangeCountCountsAgainstThePreviousVersion() {
        let model = SendProposalEditModel(proposal: makeProposal(body: "Hello one two."), constants: [], agentID: "agent")
        #expect(model.versionChangeCount(1) == nil, "v1 has no previous version")

        model.applyAgentDraft(
            makeProposal(body: "Hello three two.", subject: "Kickoff!"),
            roundTrips: 1,
            resolved: nil
        )
        #expect(model.versionChangeCount(2) == 2, "one body hunk + one subject swap")
    }

    @Test func revertingOneVersionChangeLeavesTheOtherChangesInPlace() throws {
        let model = SendProposalEditModel(proposal: makeProposal(body: "Hello one two."), constants: [], agentID: "agent")
        model.applyAgentDraft(
            makeProposal(body: "Hello three two.", subject: "Kickoff!"),
            roundTrips: 1,
            resolved: nil
        )
        let summary = try #require(model.displayedVersionChangeSummary)
        let body = try #require(summary.pairs.first { $0.kind == .body })
        let subject = try #require(summary.pairs.first { $0.kind == .subject })

        model.revertChange(body.id)
        #expect(model.tokenizedBody == "Hello one two.")
        #expect(model.subject == "Kickoff!")
        #expect(model.displayedVersionChangeSummary?.pairs.contains { $0.id == body.id } == false)
        #expect(model.displayedVersionChangeSummary?.pairs.contains { $0.id == subject.id } == true)

        model.revertChange(subject.id)
        #expect(model.subject == "Kickoff")
        #expect(model.displayedVersionChangeSummary?.pairs.isEmpty == true)
    }

    @Test func revisionConsumesPinsAndUsesTheAskOrigin() {
        let model = SendProposalEditModel(proposal: makeProposal(body: "Hello one two."), constants: [], agentID: "agent")
        model.refer(quote: "Hello one")
        model.stageAskOriginRevise(presets: ["Shorter"], note: "keep the greeting")

        model.applyAgentDraft(makeProposal(body: "Hi."), roundTrips: 1, resolved: nil)

        #expect(model.pins.isEmpty, "the revision consumed the pins")
        #expect(model.versions.last?.origin == "Ask to revise · Shorter · keep the greeting")
        #expect(model.pendingAskOrigin == nil, "the origin is consumed once used")
    }

    @Test func newestVersionOwnsChangesFromItsImmediatePredecessor() {
        let model = SendProposalEditModel(proposal: makeProposal(body: "Hello one two."), constants: [], agentID: "agent")
        model.refer(quote: "Hello one")
        model.stageAskOriginAttention()
        model.applyAgentDraft(
            makeProposal(body: "Hello three two.", subject: "Kickoff!"),
            roundTrips: 1,
            resolved: nil
        )

        let summary = model.displayedVersionChangeSummary
        #expect(summary?.fromID == 1)
        #expect(summary?.toID == 2)
        #expect(summary?.kind == "Ask to look")
        #expect(summary?.origin == "Ask to look")
        let bodyPairs = summary?.pairs.filter { $0.kind == .body }
        #expect(bodyPairs?.count == 1)
        #expect(bodyPairs?.first?.before == "Hello one")
        #expect(bodyPairs?.first?.after == "Hello three")
        #expect(summary?.pairs.contains { $0.kind == .subject && $0.before == "Kickoff" && $0.after == "Kickoff!" } == true)

        // v1 is a quiet snapshot without a summary; v2 keeps its own v1 → v2 while viewed.
        model.stepBack()
        #expect(model.displayedVersionChangeSummary == nil, "v1 is a quiet read-only snapshot")
        model.stepForward()
        #expect(model.displayedVersionChangeSummary?.fromID == 1)
        #expect(model.displayedVersionChangeSummary?.toID == 2)
    }

    @Test func changeRowsCarryPinChipNumbersAndNotes() {
        let model = SendProposalEditModel(proposal: makeProposal(body: "Hello one two."), constants: [], agentID: "agent")
        model.refer(quote: "one")
        model.pins[0].note = "make this shorter"
        model.stageAskOriginAttention()
        model.applyAgentDraft(
            makeProposal(body: "Hello three two."),
            roundTrips: 1,
            resolved: nil
        )

        let summary = model.displayedVersionChangeSummary
        #expect(summary?.rowsCarryInstructions == true)
        let bodyPair = summary?.pairs.first { $0.kind == .body }
        #expect(bodyPair?.cues.first?.number == 1)
        #expect(bodyPair?.cues.first?.note == "make this shorter")
        #expect(bodyPair?.changedPassage == "three")
        #expect(summary?.pairs.contains { $0.kind == .subject && !$0.cues.isEmpty } == false, "unpinned changes carry no cue")
    }

    @Test func askOnlyResultsStayVisibleAndMissingResultsRemainUnreported() throws {
        let proposal = makeProposal(body: "Hello one two.")
        let model = SendProposalEditModel(proposal: proposal, constants: [], agentID: "agent")
        model.refer(quote: "Hello one")
        model.pins[0].instructions = [
            ProposalPassageInstruction(
                id: "accurate",
                kind: .ask,
                label: "Check this is accurate",
                answerShape: .yesNo
            ),
            ProposalPassageInstruction(
                id: "tone",
                kind: .ask,
                label: "Check tone",
                answerShape: .choices(["Right", "Too formal", "Too casual"])
            ),
        ]
        model.stageAskOriginAttention()
        model.applyAgentDraft(
            proposal,
            roundTrips: 1,
            resolved: nil,
            results: [
                ProposalInstructionResult(
                    referenceID: "r1",
                    instructionID: "accurate",
                    status: .pass,
                    answer: .yesNo(true)
                ),
            ]
        )

        let pair = try #require(model.displayedVersionChangeSummary?.pairs.first)
        #expect(pair.kind == .result)
        #expect(pair.instructionOutcomes.count == 2)
        #expect(pair.instructionOutcomes[0].result?.status == .pass)
        #expect(pair.instructionOutcomes[0].result?.answer == .yesNo(true))
        #expect(pair.instructionOutcomes[1].result == nil, "no result must stay unreported")
    }

    @Test func pinnedPassageWidensTheRowPastTheChangedWord() {
        let v1 = """
        Hi Dana,

        Quick update on the server migration plan: we're moving to Phase 2 next Tuesday. \
        I'll send the detailed timeline tomorrow, and the rollback checklist by Friday.

        Best,
        Alex
        """
        let v2 = """
        Hi Dana,

        Quick update on the server migration initiative: we're moving to Phase 2 next Tuesday. \
        Timeline and rollback checklist by Friday.

        Best,
        Alex
        """
        let model = SendProposalEditModel(proposal: makeProposal(body: v1), constants: [], agentID: "agent")
        model.refer(quote: "server migration plan")
        model.pins[0].note = "Rewrite more formally"
        model.refer(quote: "I'll send the detailed timeline tomorrow, and the rollback checklist by Friday.")
        model.pins[1].note = "Make this shorter"
        model.stageAskOriginAttention()
        model.applyAgentDraft(makeProposal(body: v2), roundTrips: 1, resolved: nil)

        let body = model.displayedVersionChangeSummary?.pairs.filter { $0.kind == .body }
        #expect(body?.map(\.before) == [
            "server migration plan",
            "I'll send the detailed timeline tomorrow, and the rollback checklist by Friday.",
        ])
        #expect(body?.map(\.after) == [
            "server migration initiative",
            "Timeline and rollback checklist by Friday.",
        ])
        #expect(body?.map(\.changedPassage) == body?.map(\.after))
        #expect(body?.map { $0.cues.first?.number } == [1, 2])
        #expect(model.displayedChangePassages == body?.map(\.after))
    }

    @Test func thirdVersionOwnsChangesFromTheSecondVersion() {
        let model = SendProposalEditModel(proposal: makeProposal(body: "One."), constants: [], agentID: "agent")
        model.applyAgentDraft(makeProposal(body: "Two."), roundTrips: 1, resolved: nil)
        model.applyAgentDraft(makeProposal(body: "Three."), roundTrips: 2, resolved: nil)

        let summary = model.displayedVersionChangeSummary
        #expect(summary?.fromID == 2)
        #expect(summary?.toID == 3)
        #expect(summary?.kind == "Agent revision")
        #expect(summary?.origin == "Agent revision")
        #expect(summary?.pairs.first?.before == "Two.")
        #expect(summary?.pairs.first?.after == "Three.")

        // Viewing v2 shows v2's own backward diff, not v3's.
        model.stepBack()
        let v2Summary = model.displayedVersionChangeSummary
        #expect(v2Summary?.fromID == 1)
        #expect(v2Summary?.toID == 2)
        #expect(v2Summary?.pairs.first?.before == "One.")
        #expect(v2Summary?.pairs.first?.after == "Two.")
    }
}
