import Foundation
import MailStore
import Testing

struct GrantGateTests {
    @Test func denyByDefaultOmitsAllMailFromSearch() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        let page = try env.gateway.search("alpha", credential: env.credential)
        #expect(page.items.isEmpty)
    }

    @Test func accountGrantReturnsOnlyThatAccount() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.allow(agentID: env.agent.id, accountID: env.accountA)

        let page = try env.gateway.search("alpha", credential: env.credential)
        #expect(page.items.map(\.subject) == ["Alpha A"])
        #expect(page.items.map(\.accountID) == [env.accountA])
    }

    @Test func mailboxGrantOmitsOtherMailboxes() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.allow(
            agentID: env.agent.id,
            accountID: env.accountA,
            placement: "INBOX"
        )

        let inbox = try env.gateway.search("alpha", credential: env.credential)
        #expect(inbox.items.map(\.subject) == ["Alpha A"])

        let archive = try env.gateway.search("archived", credential: env.credential)
        #expect(archive.items.isEmpty)
    }
}

private struct GrantFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let accountA = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    let accountB = "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
    let agent: PairedAgent
    let grants: GrantGate
    let gateway: AgentReadAPI

    init() throws {
        root = try FixtureTree()
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: A <a@example.com>
            To: Bob <bob@example.com>
            Subject: Alpha A
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            alpha
            """,
            account: accountA,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "2.emlx",
            rfc822: """
            From: A <a@example.com>
            To: Bob <bob@example.com>
            Subject: Archived note
            Date: Tue, 2 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            archived
            """,
            account: accountA,
            mailbox: "Archive.mbox"
        )
        try root.writeEmlx(
            named: "3.emlx",
            rfc822: """
            From: B <b@example.com>
            To: Bob <bob@example.com>
            Subject: Alpha B
            Date: Wed, 3 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            alpha
            """,
            account: accountB,
            mailbox: "INBOX.mbox"
        )

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-grant-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        let pairing = Pairing()
        agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        grants = GrantGate()
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}
