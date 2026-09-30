import Foundation
import MailStore
import Testing

struct RuleStoreTests {
    @Test func snapshotRoundTripsDefinitionsAndEnablements() throws {
        let rule = GrantRule(
            id: "r1",
            name: "Invoices",
            nick: "A",
            polarity: .pass,
            fromRules: [MatchRule(value: "billing@", mode: .contains)],
            subjectRules: [MatchRule(value: "invoice", mode: .starts)],
            betweenJoin: .and,
            fields: GrantFields(envelope: false, body: true, attachmentMetadata: true),
            agentIDs: ["agent-1", "agent-2"]
        )
        let enablements = [
            RuleEnablement(ruleID: "r1", accountID: "acc-1", placement: "INBOX"),
            RuleEnablement(ruleID: "r1", accountID: "acc-1", placement: nil)
        ]
        let original = RuleSnapshot(rules: [rule], enablements: enablements)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RuleSnapshot.self, from: data)

        #expect(decoded == original)
        #expect(decoded.rules[0].nick == "A")
        #expect(decoded.rules[0].polarity == .pass)
        #expect(decoded.rules[0].betweenJoin == .and)
        #expect(decoded.rules[0].fields.body == true)
        #expect(decoded.enablements.count == 2)
        #expect(decoded.enablements[0].ruleID == "r1")
    }

    @Test func storeReplaceRestoresSnapshot() {
        let store = RuleStore()
        let rule = GrantRule(
            id: "r1",
            name: "Invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        store.replace(
            with: RuleSnapshot(
                rules: [rule],
                enablements: [RuleEnablement(ruleID: "r1", accountID: "acc-1", placement: "INBOX")]
            )
        )

        #expect(store.allRules() == [rule])
        #expect(store.isEnabled(ruleID: "r1", accountID: "acc-1", placement: "INBOX"))
        #expect(!store.isEnabled(ruleID: "r1", accountID: "acc-1", placement: "Sent"))
    }

    @Test func snapshotRoundTripsBlockAndWhen() throws {
        let rule = GrantRule(
            id: "r1",
            name: "Payroll",
            nick: "B",
            polarity: .block,
            fromRules: [MatchRule(value: "@hr.example.com", mode: .ends)],
            when: RuleWhen(after: "2026-01-01", before: nil),
            whenJoin: .or,
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let data = try JSONEncoder().encode(RuleSnapshot(rules: [rule], enablements: []))
        let decoded = try JSONDecoder().decode(RuleSnapshot.self, from: data)
        #expect(decoded.rules[0].polarity == .block)
        #expect(decoded.rules[0].when?.after == "2026-01-01")
        #expect(decoded.rules[0].whenJoin == .or)
    }

    @Test func encodedSnapshotUsesRulesKeyAndRuleID() throws {
        let rule = GrantRule(
            id: "r1",
            name: "Invoices",
            nick: "A",
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        let data = try JSONEncoder().encode(
            RuleSnapshot(
                rules: [rule],
                enablements: [RuleEnablement(ruleID: "r1", accountID: "acc-1", placement: "INBOX")]
            )
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["rules"] is [Any])
        #expect(json?["passes"] == nil)
        let enablements = json?["enablements"] as? [[String: Any]]
        #expect(enablements?.first?["ruleID"] as? String == "r1")
        #expect(enablements?.first?["passID"] == nil)
    }

}
