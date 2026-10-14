import Foundation
import MailStore

// =============================================================================
// SCREENSHOT_DEMO_POLICY — DEBUG only. Workflow: docs/agents/screenshots.md
//
// Local capture via `make screenshots`. Release CI strips this scaffolding before DMG.
// What it does: backs up live grants/rules, plants 2 fixture accounts + Shared rules A–D.
// =============================================================================

#if DEBUG

enum CompanionDemoPolicy {
    /// Application Support/MailGent/screenshot-policy-backup/
    static var backupDirectoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailGent", isDirectory: true)
            .appendingPathComponent("screenshot-policy-backup", isDirectory: true)
    }

    static var backupExists: Bool {
        let fm = FileManager.default
        let grants = backupDirectoryURL.appendingPathComponent("grants.json")
        let rules = backupDirectoryURL.appendingPathComponent("rules.json")
        return fm.fileExists(atPath: grants.path) || fm.fileExists(atPath: rules.path)
    }

    /// Two account-wide allows for Companion fixture mailboxes.
    static func grants(agentID: String) -> [Grant] {
        let fields = GrantFields.headersOnly
        return [
            Grant(
                agentID: agentID,
                accountID: CompanionAccounts.work,
                placement: nil,
                mode: .allow,
                fields: fields
            ),
            Grant(
                agentID: agentID,
                accountID: CompanionAccounts.personal,
                placement: nil,
                mode: .allow,
                fields: fields
            ),
        ]
    }

    /// Shared Pass rules (A–D) enabled account-wide on both fixture accounts → "Used on 2 placements".
    static func ruleSnapshot(agentID: String) -> RuleSnapshot {
        let rules = demoRules
        let accounts = [CompanionAccounts.work, CompanionAccounts.personal]
        let enablements = rules.flatMap { rule in
            accounts.map { accountID in
                RuleEnablement(
                    ruleID: rule.id,
                    agentID: agentID,
                    accountID: accountID,
                    placement: nil
                )
            }
        }
        return RuleSnapshot(rules: rules, enablements: enablements)
    }

    static var demoRules: [GrantRule] {
        [
            GrantRule(
                id: "demo-rule-job-offers",
                name: "job offers",
                nick: "A",
                polarity: .pass,
                fromRules: [
                    MatchRule(value: "donotreply@match.indeed.com", mode: .exact),
                    MatchRule(value: "jobalerts-noreply@linkedin.com", mode: .exact),
                    MatchRule(value: "donotreply@jobalert.indeed.com", mode: .exact),
                    MatchRule(value: "jobs-noreply@linkedin.com", mode: .exact),
                    MatchRule(value: "admin@cv-library.co.uk", mode: .exact),
                ],
                fields: revealExtras
            ),
            GrantRule(
                id: "demo-rule-properties",
                name: "properties",
                nick: "B",
                polarity: .pass,
                fromRules: [
                    MatchRule(value: "@zoopla.co.uk", mode: .ends),
                    MatchRule(value: "noreply@booking.com", mode: .exact),
                ],
                fields: revealBodyAttachments
            ),
            GrantRule(
                id: "demo-rule-itineraries",
                name: "itineraries",
                nick: "C",
                polarity: .pass,
                fromRules: [
                    MatchRule(value: "Itinerary@ryanair.com", mode: .exact),
                    MatchRule(value: "donotreply@easyjet.com", mode: .exact),
                ],
                subjectRules: [
                    MatchRule(value: "ticket confirmation", mode: .contains),
                    MatchRule(value: "booking reference", mode: .contains),
                ],
                betweenJoin: .or,
                fields: revealBodyAttachments
            ),
            GrantRule(
                id: "demo-rule-b138rj",
                name: "B138RJ",
                nick: "D",
                polarity: .pass,
                fromRules: [
                    MatchRule(value: "@ovoenergy.com", mode: .ends),
                    MatchRule(value: "@johnshepherd.com", mode: .ends),
                    MatchRule(value: "@severntrent.co.uk", mode: .ends),
                ],
                subjectRules: [
                    MatchRule(value: "OVO refund", mode: .contains),
                ],
                betweenJoin: .or,
                fields: revealBodyAttachments
            ),
        ]
    }

    /// Cc + date + body + attachment names/content (job-offers style reveal).
    private static var revealExtras: GrantFields {
        GrantFields(
            subject: false,
            from: false,
            to: false,
            cc: true,
            date: true,
            body: true,
            attachmentMetadata: true,
            attachmentContent: true
        )
    }

    private static var revealBodyAttachments: GrantFields {
        GrantFields(
            subject: false,
            from: false,
            to: false,
            cc: false,
            date: false,
            body: true,
            attachmentMetadata: true,
            attachmentContent: true
        )
    }
}

#endif
