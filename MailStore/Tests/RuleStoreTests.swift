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
            fields: GrantFields(envelope: false, body: true, attachmentMetadata: true)
        )
        let enablements = [
            RuleEnablement(ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: "INBOX"),
            RuleEnablement(ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: nil)
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
        #expect(decoded.enablements[0].agentID == "agent-1")
    }

    @Test func storeReplaceRestoresSnapshot() {
        let store = RuleStore()
        let rule = GrantRule(
            id: "r1",
            name: "Invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true)
        )
        store.replace(
            with: RuleSnapshot(
                rules: [rule],
                enablements: [
                    RuleEnablement(ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: "INBOX")
                ]
            )
        )

        #expect(store.allRules() == [rule])
        #expect(store.isEnabled(ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: "INBOX"))
        #expect(!store.isEnabled(ruleID: "r1", agentID: "agent-2", accountID: "acc-1", placement: "INBOX"))
        #expect(!store.isEnabled(ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: "Sent"))
    }

    @Test func setEnabledIsPerAgent() {
        let store = RuleStore()
        store.setEnabled(true, ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: "INBOX")
        #expect(store.isEnabled(ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: "INBOX"))
        #expect(!store.isEnabled(ruleID: "r1", agentID: "agent-2", accountID: "acc-1", placement: "INBOX"))

        store.setEnabled(true, ruleID: "r1", agentID: "agent-2", accountID: "acc-1", placement: "INBOX")
        store.setEnabled(false, ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: "INBOX")
        #expect(!store.isEnabled(ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: "INBOX"))
        #expect(store.isEnabled(ruleID: "r1", agentID: "agent-2", accountID: "acc-1", placement: "INBOX"))
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
            fields: GrantFields(envelope: false, body: true)
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
            fields: GrantFields(envelope: false, body: true)
        )
        let data = try JSONEncoder().encode(
            RuleSnapshot(
                rules: [rule],
                enablements: [
                    RuleEnablement(ruleID: "r1", agentID: "agent-1", accountID: "acc-1", placement: "INBOX")
                ]
            )
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["rules"] is [Any])
        #expect(json?["passes"] == nil)
        let enablements = json?["enablements"] as? [[String: Any]]
        #expect(enablements?.first?["ruleID"] as? String == "r1")
        #expect(enablements?.first?["agentID"] as? String == "agent-1")
        #expect(enablements?.first?["passID"] == nil)
    }

    @Test func decodesLegacyAgentIDsAndOmitsOnEncode() throws {
        let legacy = """
        {"rules":[{"id":"r1","name":"Invoices","nick":"A","polarity":"pass","fromRules":[],"subjectRules":[],"betweenJoin":"and","whenJoin":"and","fields":{"envelope":false,"body":true},"agentIDs":["orphan"]}],"enablements":[]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RuleSnapshot.self, from: legacy)
        #expect(decoded.rules.count == 1)
        #expect(decoded.rules[0].id == "r1")

        let reencoded = try JSONEncoder().encode(decoded)
        let json = try JSONSerialization.jsonObject(with: reencoded) as? [String: Any]
        let rules = json?["rules"] as? [[String: Any]]
        #expect(rules?.first?["agentIDs"] == nil)
    }

    @Test func decodesLegacyEnablementWithoutAgentIDAsEmpty() throws {
        let legacy = """
        {"rules":[],"enablements":[{"ruleID":"r1","accountID":"acc-1","placement":"INBOX"}]}
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(RuleSnapshot.self, from: legacy)
        #expect(decoded.enablements.count == 1)
        #expect(decoded.enablements[0].agentID == "")
        #expect(decoded.enablements[0].ruleID == "r1")
    }

    @Test func migrateLegacySharedEnablementsExpandsPerAgent() {
        let snapshot = RuleSnapshot(
            rules: [],
            enablements: [
                RuleEnablement(ruleID: "r1", agentID: "", accountID: "acc-1", placement: "INBOX"),
                RuleEnablement(ruleID: "r2", agentID: "keep", accountID: "acc-1", placement: nil)
            ]
        )
        let migrated = RuleStore.migrateLegacySharedEnablements(
            snapshot,
            agentIDs: ["a1", "a2"]
        )
        #expect(migrated.enablements.count == 3)
        #expect(
            migrated.enablements.contains {
                $0.ruleID == "r1" && $0.agentID == "a1" && $0.placement == "INBOX"
            }
        )
        #expect(
            migrated.enablements.contains {
                $0.ruleID == "r1" && $0.agentID == "a2" && $0.placement == "INBOX"
            }
        )
        #expect(
            migrated.enablements.contains {
                $0.ruleID == "r2" && $0.agentID == "keep"
            }
        )
        #expect(!migrated.enablements.contains { $0.agentID.isEmpty })
    }

    @Test func removeEnablementsDropsOnlyThatAgent() {
        let store = RuleStore()
        store.setEnabled(true, ruleID: "r1", agentID: "a1", accountID: "acc-1", placement: "INBOX")
        store.setEnabled(true, ruleID: "r1", agentID: "a2", accountID: "acc-1", placement: "INBOX")
        store.removeEnablements(agentID: "a1")
        #expect(!store.isEnabled(ruleID: "r1", agentID: "a1", accountID: "acc-1", placement: "INBOX"))
        #expect(store.isEnabled(ruleID: "r1", agentID: "a2", accountID: "acc-1", placement: "INBOX"))
    }
}
