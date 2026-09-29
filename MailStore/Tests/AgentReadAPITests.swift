import Foundation
import MailStore
import Testing

struct AgentReadAPITests {
    @Test func searchWithoutCredentialIsRejected() throws {
        let env = try AgentReadFixture()
        defer { env.remove() }

        #expect(throws: PairingError.unauthorized) {
            try env.gateway.search("invoice", credential: nil)
        }
    }

    @Test func searchWithWrongCredentialIsRejected() throws {
        let env = try AgentReadFixture()
        defer { env.remove() }

        #expect(throws: PairingError.unauthorized) {
            try env.gateway.search("invoice", credential: "wrong")
        }
    }

    @Test func authenticatedSearchReturnsGrantedMail() throws {
        let env = try AgentReadFixture()
        defer { env.remove() }

        let page = try env.gateway.search("invoice", credential: env.credential)
        #expect(page.items.map(\.subject) == ["Invoice due"])
    }

    @Test func matchingPassUpgradesBodyOnGet() throws {
        let env = try AgentReadFixture(
            grantFields: GrantFields(envelope: true, body: false)
        )
        defer { env.remove() }

        let withoutPass = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(withoutPass.body == .notGranted)

        env.passes.upsert(
            Pass(
                id: "p1",
                name: "Invoices",
                nick: "A",
                subjectRules: [MatchRule(value: "invoice", mode: .contains)],
                fields: GrantFields(envelope: false, body: true),
                agentIDs: [env.agentID]
            )
        )
        env.passes.setEnabled(true, passID: "p1", accountID: env.accountID, placement: "INBOX")

        let withPass = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(withPass.body == .text("Please pay"))
    }

    @Test func passDoesNotGrantAccessWithoutBaseAllow() throws {
        let env = try AgentReadFixture(grantFields: nil)
        defer { env.remove() }

        env.passes.upsert(
            Pass(
                id: "p1",
                name: "Invoices",
                nick: "A",
                subjectRules: [MatchRule(value: "invoice", mode: .contains)],
                fields: GrantFields(envelope: false, body: true),
                agentIDs: [env.agentID]
            )
        )
        env.passes.setEnabled(true, passID: "p1", accountID: env.accountID, placement: "INBOX")

        #expect(throws: PairingError.unauthorized) {
            try env.gateway.get(
                credential: env.credential,
                accountID: env.accountID,
                placement: "INBOX",
                id: "1"
            )
        }
    }

    @Test func passDoesNotUpgradeWhenSubjectMismatches() throws {
        let env = try AgentReadFixture(
            grantFields: GrantFields(envelope: true, body: false)
        )
        defer { env.remove() }

        env.passes.upsert(
            Pass(
                id: "p1",
                name: "Receipts",
                nick: "A",
                subjectRules: [MatchRule(value: "receipt", mode: .contains)],
                fields: GrantFields(envelope: false, body: true),
                agentIDs: [env.agentID]
            )
        )
        env.passes.setEnabled(true, passID: "p1", accountID: env.accountID, placement: "INBOX")

        let message = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .notGranted)
    }
}

private struct AgentReadFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    let agentID: String
    let passes: PassStore
    let gateway: AgentReadAPI

    init(grantFields: GrantFields? = .default) throws {
        root = try FixtureTree()
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Invoice due
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Please pay
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-agent-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        let pairing = Pairing()
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        agentID = agent.id
        let grants = GrantGate()
        if let grantFields {
            try grants.allow(agentID: agent.id, accountID: accountID, fields: grantFields)
        }
        passes = PassStore()
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            passes: passes
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}
