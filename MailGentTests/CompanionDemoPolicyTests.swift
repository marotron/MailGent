import Foundation
import MailStore
import Testing
@testable import MailGent

#if DEBUG

/// SCREENSHOT_DEMO_POLICY — remove with CompanionDemoPolicy.swift
struct CompanionDemoPolicyTests {
    @Test func plantsTwoAccountWideGrants() {
        let agentID = "agent-demo"
        let grants = CompanionDemoPolicy.grants(agentID: agentID)
        #expect(grants.count == 2)
        #expect(Set(grants.map(\.accountID)) == [
            CompanionAccounts.work,
            CompanionAccounts.personal,
        ])
        #expect(grants.allSatisfy { $0.placement == nil && $0.mode == .allow })
        #expect(grants.allSatisfy { $0.agentID == agentID })
    }

    @Test func rulesEnabledOnBothAccountsOnly() {
        let agentID = "agent-demo"
        let snapshot = CompanionDemoPolicy.ruleSnapshot(agentID: agentID)
        #expect(snapshot.rules.map(\.nick) == ["A", "B", "C", "D"])
        #expect(snapshot.rules.count == 4)

        let keys = Set(
            snapshot.enablements.map { "\($0.ruleID)|\($0.accountID)|\($0.placement ?? "*")" }
        )
        #expect(keys.count == 8) // 4 rules × 2 accounts
        #expect(snapshot.enablements.allSatisfy { $0.placement == nil })
        #expect(snapshot.enablements.allSatisfy { $0.agentID == agentID })

        for rule in snapshot.rules {
            let n = snapshot.enablements.filter { $0.ruleID == rule.id }.count
            #expect(n == 2)
        }
    }
}

#endif
