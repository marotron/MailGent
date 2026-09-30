import Foundation
import MailStore
import Testing

struct RuleEngineTests {
    @Test func containsSubjectRuleUpgradesBodyOntoHeadersOnlyBase() {
        let message = sampleMessage(from: "alice@example.com", subject: "Invoice due Friday")
        let pass = GrantRule(
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
            RuleEnablement(ruleID: "p1", accountID: message.accountID, placement: message.placement)
        ]

        let upgraded = RuleEngine.applyOverlays(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            rules: [pass],
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
            RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")
        ]

        #expect(
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [
                    GrantRule(
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
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [
                    GrantRule(
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
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [
                    GrantRule(
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
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [
                    GrantRule(
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
        let pass = GrantRule(
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

        let upgraded = RuleEngine.applyOverlays(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            rules: [pass],
            enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]
        )
        #expect(upgraded.body == true)
    }

    @Test func betweenANDRequiresBothGroupsWhenBothPresent() {
        let message = sampleMessage(from: "alice@example.com", subject: "Invoice due")
        let pass = GrantRule(
            id: "p1",
            name: "Alice invoices",
            nick: "A",
            fromRules: [MatchRule(value: "bob@", mode: .contains)],
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            betweenJoin: .and,
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]

        #expect(
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [pass],
                enablements: enablements
            ).body == false
        )

        let matchingFrom = GrantRule(
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
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [matchingFrom],
                enablements: enablements
            ).body == true
        )
    }

    @Test func betweenORMatchesEitherGroup() {
        let message = sampleMessage(from: "alice@example.com", subject: "Hello")
        let pass = GrantRule(
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
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [pass],
                enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]
            ).body == true
        )
    }

    @Test func skipsWhenAgentNotOnGrantRule() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice")
        let pass = GrantRule(
            id: "p1",
            name: "Invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["other-agent"]
        )

        #expect(
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [pass],
                enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]
            ).body == false
        )
    }

    @Test func skipsWhenPlacementNotEnabled() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice")
        let pass = GrantRule(
            id: "p1",
            name: "Invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        #expect(
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [pass],
                enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "Sent")]
            ).body == false
        )
    }

    @Test func accountWideEnablementCoversAnyPlacement() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice")
        let pass = GrantRule(
            id: "p1",
            name: "Invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        #expect(
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [pass],
                enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: nil)]
            ).body == true
        )
    }

    @Test func multiPassUnionsFields() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice attachment")
        let bodyPass = GrantRule(
            id: "p1",
            name: "Body",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let attPass = GrantRule(
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
            RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX"),
            RuleEnablement(ruleID: "p2", accountID: "acc-1", placement: "INBOX")
        ]

        let upgraded = RuleEngine.applyOverlays(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            rules: [bodyPass, attPass],
            enablements: enablements
        )
        #expect(upgraded.body == true)
        #expect(upgraded.attachmentMetadata == true)
    }

    @Test func redundantPassLeavesBaseUnchangedWhenAlreadyCovered() {
        let message = sampleMessage(from: "a@x.com", subject: "Invoice")
        let pass = GrantRule(
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

        let upgraded = RuleEngine.applyOverlays(
            base: base,
            message: message,
            agentID: "agent-1",
            rules: [pass],
            enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]
        )
        #expect(upgraded == base)
    }

    @Test func emptyRulesNeverMatch() {
        let message = sampleMessage(from: "alice@example.com", subject: "Hello")
        let pass = GrantRule(
            id: "p1",
            name: "Incomplete",
            nick: "A",
            fromRules: [],
            subjectRules: [],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        let upgraded = RuleEngine.applyOverlays(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            rules: [pass],
            enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]
        )
        #expect(upgraded == .headersOnly)
        #expect(upgraded.body == false)
    }

    @Test func blockSubtractsFieldsAfterPassUnion() {
        let message = sampleMessage(from: "hr@example.com", subject: "payslip PDF", date: "2026-06-15T12:00:00Z")
        let pass = GrantRule(
            id: "p1",
            name: "Reveal body",
            nick: "A",
            polarity: .pass,
            subjectRules: [MatchRule(value: "payslip", mode: .contains)],
            fields: GrantFields(envelope: false, body: true, attachmentMetadata: true, attachmentContent: true),
            agentIDs: ["agent-1"]
        )
        let block = GrantRule(
            id: "p2",
            name: "Hide attachments",
            nick: "B",
            polarity: .block,
            fromRules: [MatchRule(value: "@example.com", mode: .ends)],
            fields: GrantFields(
                subject: false,
                from: false,
                to: false,
                cc: false,
                date: false,
                body: false,
                attachmentMetadata: true,
                attachmentContent: true
            ),
            agentIDs: ["agent-1"]
        )
        let enablements = [
            RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX"),
            RuleEnablement(ruleID: "p2", accountID: "acc-1", placement: "INBOX")
        ]

        let result = RuleEngine.applyOverlays(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            rules: [pass, block],
            enablements: enablements
        )
        #expect(result.body == true)
        #expect(result.attachmentMetadata == false)
        #expect(result.attachmentContent == false)
    }

    @Test func applyOverlaysWithAppliedListsPassThatNewlyGrantsField() {
        let message = sampleMessage(from: "alice@example.com", subject: "Invoice due Friday")
        let pass = GrantRule(
            id: "p1",
            name: "Invoices",
            nick: "A",
            polarity: .pass,
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [
            RuleEnablement(ruleID: "p1", accountID: message.accountID, placement: message.placement)
        ]

        let (fields, applied) = RuleEngine.applyOverlaysWithApplied(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            rules: [pass],
            enablements: enablements
        )

        #expect(fields.body == true)
        #expect(applied == [
            AppliedGrantRule(
                id: "p1",
                nick: "A",
                polarity: .pass,
                fields: GrantFields(envelope: false, body: true)
            )
        ])
    }

    @Test func applyOverlaysWithAppliedOmitsPassWhenFieldsAlreadyCovered() {
        let message = sampleMessage(from: "alice@example.com", subject: "Invoice due Friday")
        let pass = GrantRule(
            id: "p1",
            name: "Invoices",
            nick: "A",
            polarity: .pass,
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [
            RuleEnablement(ruleID: "p1", accountID: message.accountID, placement: message.placement)
        ]
        let base = GrantFields(envelope: true, body: true)

        let (fields, applied) = RuleEngine.applyOverlaysWithApplied(
            base: base,
            message: message,
            agentID: "agent-1",
            rules: [pass],
            enablements: enablements
        )

        #expect(fields.body == true)
        #expect(applied.isEmpty)
    }

    @Test func applyOverlaysWithAppliedListsBlockThatWithholdsGrantedField() {
        let message = sampleMessage(from: "hr@example.com", subject: "payslip PDF")
        let block = GrantRule(
            id: "b1",
            name: "Hide body",
            nick: "B",
            polarity: .block,
            subjectRules: [MatchRule(value: "payslip", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [
            RuleEnablement(ruleID: "b1", accountID: message.accountID, placement: message.placement)
        ]
        let base = GrantFields(envelope: true, body: true)

        let (fields, applied) = RuleEngine.applyOverlaysWithApplied(
            base: base,
            message: message,
            agentID: "agent-1",
            rules: [block],
            enablements: enablements
        )

        #expect(fields.body == false)
        #expect(applied == [
            AppliedGrantRule(
                id: "b1",
                nick: "B",
                polarity: .block,
                fields: GrantFields(envelope: false, body: true)
            )
        ])
    }

    @Test func applyOverlaysWithAppliedOmitsBlockWhenFieldsAlreadyOff() {
        let message = sampleMessage(from: "hr@example.com", subject: "payslip PDF")
        let block = GrantRule(
            id: "b1",
            name: "Hide body",
            nick: "B",
            polarity: .block,
            subjectRules: [MatchRule(value: "payslip", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [
            RuleEnablement(ruleID: "b1", accountID: message.accountID, placement: message.placement)
        ]

        let (fields, applied) = RuleEngine.applyOverlaysWithApplied(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            rules: [block],
            enablements: enablements
        )

        #expect(fields.body == false)
        #expect(applied.isEmpty)
    }

    @Test func applyOverlaysWithAppliedListsPassThenBlockWhenEachChangesFields() {
        let message = sampleMessage(from: "hr@example.com", subject: "payslip PDF")
        let pass = GrantRule(
            id: "p1",
            name: "Reveal body",
            nick: "A",
            polarity: .pass,
            subjectRules: [MatchRule(value: "payslip", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let block = GrantRule(
            id: "b1",
            name: "Hide body",
            nick: "B",
            polarity: .block,
            subjectRules: [MatchRule(value: "payslip", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [
            RuleEnablement(ruleID: "p1", accountID: message.accountID, placement: message.placement),
            RuleEnablement(ruleID: "b1", accountID: message.accountID, placement: message.placement)
        ]

        let (fields, applied) = RuleEngine.applyOverlaysWithApplied(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            rules: [pass, block],
            enablements: enablements
        )

        #expect(fields.body == false)
        #expect(applied == [
            AppliedGrantRule(
                id: "p1",
                nick: "A",
                polarity: .pass,
                fields: GrantFields(envelope: false, body: true)
            ),
            AppliedGrantRule(
                id: "b1",
                nick: "B",
                polarity: .block,
                fields: GrantFields(envelope: false, body: true)
            )
        ])
    }

    @Test func whenWindowANDedWithMatchers() {
        let inWindow = sampleMessage(from: "billing@x.com", subject: "Invoice", date: "2026-03-10T10:00:00Z")
        let outWindow = sampleMessage(from: "billing@x.com", subject: "Invoice", date: "2025-03-10T10:00:00Z")
        let pass = GrantRule(
            id: "p1",
            name: "Recent invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            when: RuleWhen(after: "2026-01-01", before: "2026-12-31"),
            whenJoin: .and,
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]

        #expect(
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: inWindow,
                agentID: "agent-1",
                rules: [pass],
                enablements: enablements
            ).body == true
        )
        #expect(
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: outWindow,
                agentID: "agent-1",
                rules: [pass],
                enablements: enablements
            ).body == false
        )
    }

    @Test func whenOnlyRuleMatchesDateWindow() {
        let message = sampleMessage(from: "anyone@x.com", subject: "Hello", date: "2026-02-01T00:00:00Z")
        let pass = GrantRule(
            id: "p1",
            name: "2026 mail",
            nick: "A",
            when: RuleWhen(after: "2026-01-01"),
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        #expect(
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [pass],
                enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]
            ).body == true
        )
    }

    @Test func fromEndsMatchesDisplayNameAngleAddrForm() {
        let message = sampleMessage(
            from: "OVO Energy <no-reply@ovoenergy.com>",
            subject: "Your final bill has arrived"
        )
        let pass = GrantRule(
            id: "p1",
            name: "B138RJ",
            nick: "D",
            polarity: .pass,
            fromRules: [MatchRule(value: "@ovoenergy.com", mode: .ends)],
            fields: GrantFields(envelope: false, body: true, attachmentMetadata: true, attachmentContent: true),
            agentIDs: ["agent-1"]
        )
        let enablements = [
            RuleEnablement(ruleID: "p1", accountID: message.accountID, placement: message.placement)
        ]

        let fields = RuleEngine.applyOverlays(
            base: .headersOnly,
            message: message,
            agentID: "agent-1",
            rules: [pass],
            enablements: enablements
        )
        #expect(fields.body == true)
        #expect(fields.attachmentMetadata == true)
        #expect(fields.attachmentContent == true)
    }

    @Test func fromExactMatchesDisplayNameAngleAddrForm() {
        let message = sampleMessage(
            from: "OVO Energy <no-reply@ovoenergy.com>",
            subject: "Your final bill has arrived"
        )
        let pass = GrantRule(
            id: "p1",
            name: "Exact OVO",
            nick: "E",
            polarity: .pass,
            fromRules: [MatchRule(value: "no-reply@ovoenergy.com", mode: .exact)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )

        #expect(
            RuleEngine.applyOverlays(
                base: .headersOnly,
                message: message,
                agentID: "agent-1",
                rules: [pass],
                enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]
            ).body == true
        )
    }

    @Test func passOverwriteIrrelevantWhenBaseAlreadyGrantsField() {
        let message = sampleMessage(from: "alice@example.com", subject: "Hi")
        let pass = GrantRule(
            id: "p1",
            name: "Body",
            nick: "A",
            polarity: .pass,
            subjectRules: [MatchRule(value: "Hi", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let (_, applied) = RuleEngine.applyOverlaysWithApplied(
            base: .default,
            message: message,
            agentID: "agent-1",
            rules: [pass],
            enablements: [RuleEnablement(ruleID: "p1", accountID: "acc-1", placement: "INBOX")]
        )
        #expect(applied.isEmpty)
    }
}

private func sampleMessage(from: String, subject: String, date: String = "2024-01-01T00:00:00Z") -> IndexedMessage {
    IndexedMessage(
        id: "1",
        accountID: "acc-1",
        placement: "INBOX",
        from: from,
        to: "bob@example.com",
        cc: "",
        date: date,
        subject: subject,
        body: "body",
        isPartial: false
    )
}
