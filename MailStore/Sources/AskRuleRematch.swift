import Foundation

/// Whether a newly committed Ask rule should force another open Ask to re-run grant→rules→Ask.
public enum AskRuleRematch {
    /// True when the rule matches this Ask's message + enablement and covers any field the Ask is waiting on.
    public static func shouldRecheck(
        rule: GrantRule,
        enablements: [RuleEnablement],
        context: ConditionalAccessPromptContext
    ) -> Bool {
        let message = context.matcherProbeMessage()
        guard RuleEngine.matches(
            rule,
            message: message,
            agentID: context.agentID,
            enablements: enablements
        ) else {
            return false
        }
        let covered = Set(onFieldLabels(rule.fields))
        return !covered.isDisjoint(with: Set(context.requestedFields))
    }

    /// Labels whose mode is `.on` on the rule overlay (Pass grant / Block deny bits).
    public static func onFieldLabels(_ fields: GrantFields) -> [String] {
        var result: [String] = []
        if fields.subject { result.append("Subject") }
        if fields.from { result.append("From") }
        if fields.to { result.append("To") }
        if fields.cc { result.append("Cc") }
        if fields.date { result.append("Date") }
        if fields.body { result.append("Body") }
        if fields.attachmentMetadata { result.append("Attachment names") }
        if fields.attachmentContent { result.append("Attachment content") }
        return result
    }
}
