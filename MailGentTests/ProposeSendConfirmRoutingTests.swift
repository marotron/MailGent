import MailStore
import Testing
@testable import MailGent

struct ProposeSendConfirmRoutingTests {
    @Test func editExperimentalOnAlwaysYieldsExtendedLaunch() {
        let launch = ProposeSendConfirmRouting.editLaunch(
            editExperimental: true,
            constants: [],
            agentID: "agent",
            shortcut: .defaultShortcut,
            notePresets: [],
            roundTrips: 0
        )
        #expect(launch != nil)
        #expect(launch?.agentID == "agent")
        #expect(launch?.roundTrips == 0)
    }

    @Test func editExperimentalOffYieldsSimpleConfirmPath() {
        let launch = ProposeSendConfirmRouting.editLaunch(
            editExperimental: false,
            constants: [],
            agentID: "agent",
            shortcut: .defaultShortcut,
            notePresets: ["tighten"],
            roundTrips: 2
        )
        #expect(launch == nil)
    }
}
