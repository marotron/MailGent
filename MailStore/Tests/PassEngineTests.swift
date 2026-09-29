import Foundation
import MailStore
import Testing

struct PassEngineTests {
    @Test func containsSubjectRuleUpgradesBodyOntoHeadersOnlyBase() {
        let message = sampleMessage(from: "alice@example.com", subject: "Invoice due Friday")
        let pass = Pass(
            id: "p1",
            name: "Invoices",
            nick: "A",
            fromRules: [],
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            betweenJoin: .and,
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [
            PassEnablement(passID: "p1", accountID: message.accountID, placement: message.placement)
        ]

        let upgraded = PassEngine.upgrade(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            passes: [pass],
            enablements: enablements
        )

        #expect(upgraded.subject == true)
        #expect(upgraded.from == true)
        #expect(upgraded.body == true)
        #expect(upgraded.attachmentMetadata == false)
    }

    @Test func startsEndsExactModesMatchAsSpecified() {
        let message = sampleMessage(from: "billing@acme.com", subject: "Invoice-42")
        let enablements = [
            PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX")
        ]

        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [
                    Pass(
                        id: "p1",
                        name: "Starts",
                        nick: "A",
                        subjectRules: [MatchRule(value: "Inv", mode: .starts)],
                        fields: GrantFields(envelope: false, body: true),
                        agentIDs: ["agent-1"]
                    )
                ],
                enablements: enablements
            ).body == true
        )
        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [
                    Pass(
                        id: "p1",
                        name: "Ends",
                        nick: "A",
                        subjectRules: [MatchRule(value: "-42", mode: .ends)],
                        fields: GrantFields(envelope: false, body: true),
                        agentIDs: ["agent-1"]
                    )
                ],
                enablements: enablements
            ).body == true
        )
        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [
                    Pass(
                        id: "p1",
                        name: "Exact",
                        nick: "A",
                        subjectRules: [MatchRule(value: "Invoice-42", mode: .exact)],
                        fields: GrantFields(envelope: false, body: true),
                        agentIDs: ["agent-1"]
                    )
                ],
                enablements: enablements
            ).body == true
        )
        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [
                    Pass(
                        id: "p1",
                        name: "Exact miss",
                        nick: "A",
                        subjectRules: [MatchRule(value: "Invoice", mode: .exact)],
                        fields: GrantFields(envelope: false, body: true),
                        agentIDs: ["agent-1"]
                    )
                ],
                enablements: enablements
            ).body == false
        )
    }

    @Test func withinGroupRulesAreOR() {
        let message = sampleMessage(from: "alice@example.com", subject: "Receipt from store")
        let pass = Pass(
            id: "p1",
            name: "Receipts",
            nick: "A",
            subjectRules: [
                MatchRule(value: "invoice", mode: .contains),
                MatchRule(value: "receipt", mode: .contains)
            ],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        let upgraded = PassEngine.upgrade(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            passes: [pass],
            enablements: [PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX")]
        )
        #expect(upgraded.body == true)
    }

    @Test func betweenANDRequiresBothGroupsWhenBothPresent() {
        let message = sampleMessage(from: "alice@example.com", subject: "Invoice due")
        let pass = Pass(
            id: "p1",
            name: "Alice invoices",
            nick: "A",
            fromRules: [MatchRule(value: "bob@", mode: .contains)],
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            betweenJoin: .and,
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX")]

        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [pass],
                enablements: enablements
            ).body == false
        )

        let matchingFrom = Pass(
            id: "p1",
            name: "Alice invoices",
            nick: "A",
            fromRules: [MatchRule(value: "alice@", mode: .contains)],
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            betweenJoin: .and,
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [matchingFrom],
                enablements: enablements
            ).body == true
        )
    }

    @Test func betweenORMatchesEitherGroup() {
        let message = sampleMessage(from: "alice@example.com", subject: "Hello")
        let pass = Pass(
            id: "p1",
            name: "Either",
            nick: "A",
            fromRules: [MatchRule(value: "alice@", mode: .contains)],
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            betweenJoin: .or,
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [pass],
                enablements: [PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX")]
            ).body == true
        )
    }

    @Test func skipsWhenAgentNotOnPass() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice")
        let pass = Pass(
            id: "p1",
            name: "Invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["other-agent"]
        )

        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [pass],
                enablements: [PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX")]
            ).body == false
        )
    }

    @Test func skipsWhenPlacementNotEnabled() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice")
        let pass = Pass(
            id: "p1",
            name: "Invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [pass],
                enablements: [PassEnablement(passID: "p1", accountID: "acc-1", placement: "Sent")]
            ).body == false
        )
    }

    @Test func accountWideEnablementCoversAnyPlacement() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice")
        let pass = Pass(
            id: "p1",
            name: "Invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        #expect(
            PassEngine.upgrade(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                passes: [pass],
                enablements: [PassEnablement(passID: "p1", accountID: "acc-1", placement: nil)]
            ).body == true
        )
    }

    @Test func multiPassUnionsFields() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice attachment")
        let bodyPass = Pass(
            id: "p1",
            name: "Body",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let attPass = Pass(
            id: "p2",
            name: "Att",
            nick: "B",
            subjectRules: [MatchRule(value: "attachment", mode: .contains)],
            fields: GrantFields(
                subject: false,
                from: false,
                to: false,
                cc: false,
                date: false,
                body: false,
                attachmentMetadata: true
            ),
            agentIDs: ["agent-1"]
        )
        let enablements = [
            PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX"),
            PassEnablement(passID: "p2", accountID: "acc-1", placement: "INBOX")
        ]

        let upgraded = PassEngine.upgrade(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            passes: [bodyPass, attPass],
            enablements: enablements
        )
        #expect(upgraded.body == true)
        #expect(upgraded.attachmentMetadata == true)
    }

    @Test func redundantPassLeavesBaseUnchangedWhenAlreadyCovered() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice")
        let pass = Pass(
            id: "p1",
            name: "Body",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let base = GrantFields(
            subject: true,
            from: true,
            to: true,
            cc: true,
            date: true,
            body: true
        )

        let upgraded = PassEngine.upgrade(
            base: base,
            message: message,
            agentID: "agent-1",
            passes: [pass],
            enablements: [PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX")]
        )
        #expect(upgraded == base)
    }

    @Test func emptyRulesNeverMatch() {
        let message = sampleMessage(from: "alice@example.com", subject: "Hello")
        let pass = Pass(
            id: "p1",
            name: "Incomplete",
            nick: "A",
            fromRules: [],
            subjectRules: [],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        let upgraded = PassEngine.upgrade(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            passes: [pass],
            enablements: [PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX")]
        )
        #expect(upgraded == .headersOnly)
        #expect(upgraded.body == false)
    }
}

private func sampleMessage(from: String, subject: String) -> IndexedMessage {
    IndexedMessage(
        id: "1",
        accountID: "acc-1",
        placement: "INBOX",
        from: from,
        to: "bob@example.com",
        cc: "",
        date: "2024-01-01T00:00:00Z",
        subject: subject,
        body: "body",
        isPartial: false
    )
}
