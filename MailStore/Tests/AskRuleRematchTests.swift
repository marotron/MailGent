import Foundation
import MailStore
import Testing

@Suite struct AskRuleRematchTests {
    @Test func shouldRecheckWhenMatchEnablementAndFieldIntersect() {
        let context = sampleContext(requestedFields: ["Body", "Attachment content"])
        let rule = sampleRule(fields: GrantFields(envelope: false, body: true))
        let enablements = [
            RuleEnablement(
                ruleID: rule.id,
                agentID: context.agentID,
                accountID: context.accountID,
                placement: context.placement
            )
        ]

        #expect(AskRuleRematch.shouldRecheck(rule: rule, enablements: enablements, context: context))
    }

    @Test func shouldRecheckFalseWhenMatchersMiss() {
        let context = sampleContext(requestedFields: ["Body"], from: "other@example.com")
        let rule = sampleRule(fields: GrantFields(envelope: false, body: true))
        let enablements = [
            RuleEnablement(
                ruleID: rule.id,
                agentID: context.agentID,
                accountID: context.accountID,
                placement: context.placement
            )
        ]

        #expect(!AskRuleRematch.shouldRecheck(rule: rule, enablements: enablements, context: context))
    }

    @Test func shouldRecheckFalseWhenNoFieldIntersect() {
        let context = sampleContext(requestedFields: ["Attachment content"])
        let rule = sampleRule(fields: GrantFields(envelope: false, body: true))
        let enablements = [
            RuleEnablement(
                ruleID: rule.id,
                agentID: context.agentID,
                accountID: context.accountID,
                placement: context.placement
            )
        ]

        #expect(!AskRuleRematch.shouldRecheck(rule: rule, enablements: enablements, context: context))
    }

    @Test func shouldRecheckFalseWhenEnablementMisses() {
        let context = sampleContext(requestedFields: ["Body"])
        let rule = sampleRule(fields: GrantFields(envelope: false, body: true))
        let enablements = [
            RuleEnablement(
                ruleID: rule.id,
                agentID: "other-agent",
                accountID: context.accountID,
                placement: context.placement
            )
        ]

        #expect(!AskRuleRematch.shouldRecheck(rule: rule, enablements: enablements, context: context))
    }

    @Test func shouldRecheckWorksForBlockPolarity() {
        let context = sampleContext(requestedFields: ["Body", "Subject"])
        let rule = sampleRule(
            polarity: .block,
            fields: GrantFields(envelope: false, body: true)
        )
        let enablements = [
            RuleEnablement(
                ruleID: rule.id,
                agentID: context.agentID,
                accountID: context.accountID,
                placement: context.placement
            )
        ]

        #expect(AskRuleRematch.shouldRecheck(rule: rule, enablements: enablements, context: context))
    }
}

private func sampleContext(
    requestedFields: [String],
    from: String = "alice@example.com"
) -> ConditionalAccessPromptContext {
    ConditionalAccessPromptContext(
        agentID: "agent-1",
        agentName: "Cursor",
        accountID: "acc-1",
        placement: "INBOX",
        messageID: "msg-1",
        requestedFields: requestedFields,
        fieldPreviews: requestedFields.map { ConditionalFieldPreviewLine(label: $0, value: "x") },
        envelope: ConditionalMessageEnvelope(
            subject: "Invoice due",
            from: from,
            to: "bob@example.com",
            date: "2024-01-01T00:00:00Z"
        )
    )
}

private func sampleRule(
    polarity: RulePolarity = .pass,
    fields: GrantFields
) -> GrantRule {
    GrantRule(
        id: "rule-1",
        name: "From ask",
        nick: "A",
        polarity: polarity,
        fromRules: [MatchRule(value: "alice@example.com", mode: .exact)],
        fields: fields
    )
}
