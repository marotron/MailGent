import Foundation
import MailStore
import Testing

struct AuditLogTests {
    @Test func searchAppendsAuditEntryInspectableByAPI() throws {
        let env = try AuditFixture()
        defer { env.remove() }

        _ = try env.gateway.search("invoice", credential: env.credential)

        let searches = env.audit.entries().filter { $0.kind == .search }
        #expect(searches.count == 1)
        #expect(searches[0].agentName == "Cursor")
        #expect(searches[0].detail == "invoice")
    }

    @Test func getAppendsAuditEntry() throws {
        let env = try AuditFixture()
        defer { env.remove() }

        let hit = try env.gateway.search("invoice", credential: env.credential).items[0]
        _ = try env.gateway.get(
            credential: env.credential,
            accountID: hit.accountID,
            placement: hit.placement,
            id: hit.id
        )

        let kinds = env.audit.entries().map(\.kind)
        #expect(kinds == [.pair, .search, .get])
    }

    @Test func pairAndRevokeAreAudited() throws {
        let audit = AuditLog()
        let pairing = Pairing(audit: audit)
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: "secret"
        )
        pairing.revoke(agentID: agent.id)

        #expect(audit.entries().map(\.kind) == [.pair, .revoke])
        #expect(audit.entries().map(\.agentName) == ["Cursor", "Cursor"])
    }
}

private struct AuditFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let audit: AuditLog
    let gateway: AgentReadAPI

    init() throws {
        root = try FixtureTree()
        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
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
            .appendingPathComponent("MailGent-audit-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        audit = AuditLog()
        let pairing = Pairing(audit: audit)
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        let grants = GrantGate()
        try grants.allow(agentID: agent.id, accountID: accountID)
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            audit: audit
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}
