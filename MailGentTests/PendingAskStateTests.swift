import Testing
@testable import MailGent

struct PendingAskStateTests {
    @Test func registeringConcurrentRequestsPreservesOrderAndSummaries() {
        var state = PendingAskState()

        state.register(id: "first", agent: "Cursor", subject: "Payslip April")
        state.register(id: "second", agent: "Grok", subject: "")

        #expect(state.count == 2)
        #expect(
            state.summaries == [
                PendingAskSummary(id: "first", agent: "Cursor", subject: "Payslip April", kind: .ask),
                PendingAskSummary(id: "second", agent: "Grok", subject: "(no subject)", kind: .ask),
            ]
        )
        #expect(state.selectedID == "first")
    }

    @Test func selectingARowChangesSelectionWithoutADecision() {
        var state = PendingAskState()
        state.register(id: "first", agent: "Cursor", subject: "Payslip April")
        state.register(id: "second", agent: "Grok", subject: "Contract")

        let decision = state.select(id: "second")

        #expect(decision == nil)
        #expect(state.selectedID == "second")
        #expect(state.count == 2)
    }

    @Test func resolvingByIDRemovesOnlyThatRequest() {
        var state = PendingAskState()
        state.register(id: "first", agent: "Cursor", subject: "Payslip April")
        state.register(id: "second", agent: "Grok", subject: "Contract")

        let decision = state.resolve(id: "first", with: .allow)

        #expect(decision == .allow)
        #expect(state.summaries.map(\.id) == ["second"])
        #expect(state.selectedID == "second")
        #expect(state.resolve(id: "first", with: .block) == nil)
        #expect(state.count == 1)
    }

    @Test func removeDropsRequestWithoutAllowOrBlock() {
        var state = PendingAskState()
        state.register(id: "first", agent: "Cursor", subject: "Payslip April")
        state.register(id: "second", agent: "Grok", subject: "Contract")

        let removed = state.remove(id: "first")
        #expect(removed)
        #expect(state.summaries.map(\.id) == ["second"])
        #expect(state.selectedID == "second")
        let again = state.remove(id: "first")
        #expect(!again)
    }

    @Test func closingAWindowBlocksOnlyThatRequest() {
        var state = PendingAskState()
        state.register(id: "first", agent: "Cursor", subject: "Payslip April")
        state.register(id: "second", agent: "Grok", subject: "Contract")
        _ = state.select(id: "second")

        let decision = state.close(id: "second")

        #expect(decision == .block)
        #expect(state.summaries.map(\.id) == ["first"])
        #expect(state.selectedID == "first")
    }

    @Test func accessRequestMenuIsHiddenWhenNothingIsPending() {
        let menu = AccessRequestMenu.project(PendingAskState())

        #expect(menu.isVisible == false)
        #expect(menu.count == 0)
        #expect(menu.rows.isEmpty)
        #expect(menu.accessibilityPhrase == nil)
    }

    @Test func accessRequestMenuListsStableRowsAndSelection() {
        var state = PendingAskState()
        state.register(id: "first", agent: "Cursor", subject: "Payslip April")
        state.register(id: "second", agent: "Grok", subject: "Contract draft for Project Marigold")
        _ = state.select(id: "second")

        let menu = AccessRequestMenu.project(state)

        #expect(menu.isVisible)
        #expect(menu.count == 2)
        #expect(
            menu.rows == [
                AccessRequestMenu.Row(
                    id: "first",
                    label: "Cursor · Payslip April",
                    kind: .ask,
                    isSelected: false
                ),
                AccessRequestMenu.Row(
                    id: "second",
                    label: "Grok · Contract draft for Project Marigold",
                    kind: .ask,
                    isSelected: true
                ),
            ]
        )
        #expect(menu.accessibilityPhrase == "2 items need your action")
        #expect(AccessRequestMenu.phrase(for: 1) == "1 item needs your action")
    }

    @Test func proposeSendAndAskShareBadgeCountAndKindAwareLabels() {
        var state = PendingAskState()
        state.register(id: "ask-1", agent: "Cursor", subject: "Payslip", kind: .ask)
        state.register(
            id: "send-1",
            agent: "Grok Bot",
            subject: "Re: Lindsay",
            kind: .proposeSend
        )

        #expect(state.count == 2)
        let menu = AccessRequestMenu.project(state)
        #expect(menu.count == 2)
        #expect(
            menu.rows == [
                AccessRequestMenu.Row(
                    id: "ask-1",
                    label: "Cursor · Payslip",
                    kind: .ask,
                    isSelected: true
                ),
                AccessRequestMenu.Row(
                    id: "send-1",
                    label: "Grok Bot · Send · Re: Lindsay",
                    kind: .proposeSend,
                    isSelected: false
                ),
            ]
        )
    }
}
