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

    @Test func listReturnsAllowsForAgent() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.allow(agentID: env.agent.id, accountID: env.accountA, placement: "INBOX")
        try env.grants.allow(agentID: env.agent.id, accountID: env.accountB)

        let listed = env.grants.list(agentID: env.agent.id)
        #expect(listed.count == 2)
        #expect(listed.contains { $0.accountID == env.accountA && $0.placement == "INBOX" })
        #expect(listed.contains { $0.accountID == env.accountB && $0.placement == nil })
        #expect(env.grants.list(agentID: "missing").isEmpty)
    }

    @Test func replaceAllRestoresPersistedAllows() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        let snapshot = [
            Grant(agentID: env.agent.id, accountID: env.accountA, placement: "INBOX"),
            Grant(agentID: env.agent.id, accountID: env.accountB)
        ]
        env.grants.replaceAll(agentID: env.agent.id, with: snapshot)

        let page = try env.gateway.search("alpha", credential: env.credential)
        #expect(Set(page.items.map(\.subject)) == ["Alpha A", "Alpha B"])

        let archive = try env.gateway.search("archived", credential: env.credential)
        #expect(archive.items.isEmpty)

        #expect(env.grants.list(agentID: env.agent.id) == snapshot)
    }

    @Test func grantSnapshotRoundTripsThroughJSON() throws {
        let agentID = "agent-1"
        let snapshot = GrantSnapshot(grants: [
            Grant(agentID: agentID, accountID: "acc-a", placement: "INBOX"),
            Grant(agentID: agentID, accountID: "acc-b")
        ])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(GrantSnapshot.self, from: data)
        #expect(decoded == snapshot)
    }

    @Test func fromAddressSelectorOmitsOtherSenders() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.allow(
            agentID: env.agent.id,
            accountID: env.accountA,
            participants: [
                GrantParticipant(role: .from, address: "a@example.com")
            ]
        )

        let page = try env.gateway.search("alpha", credential: env.credential)
        #expect(page.items.map(\.subject) == ["Alpha A"])

        // Account B also has "alpha" but different From — must not appear (no grant).
        #expect(!page.items.contains { $0.accountID == env.accountB })
    }

    @Test func dateRangeSelectorOmitsOlderMail() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.allow(
            agentID: env.agent.id,
            accountID: env.accountA,
            dateStart: "2024-01-02T00:00:00Z",
            dateEnd: nil
        )

        let page = try env.gateway.search("a", credential: env.credential)
        #expect(page.items.map(\.subject) == ["Archived note"])
    }

    @Test func denyCarveOutSubtractsFromBroaderAllow() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.allow(agentID: env.agent.id, accountID: env.accountA)
        try env.grants.deny(
            agentID: env.agent.id,
            accountID: env.accountA,
            placement: "Archive"
        )

        let inbox = try env.gateway.search("alpha", credential: env.credential)
        #expect(inbox.items.map(\.subject) == ["Alpha A"])

        let archive = try env.gateway.search("archived", credential: env.credential)
        #expect(archive.items.isEmpty)
    }

    @Test func denyAloneDoesNotGrantAccess() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.deny(agentID: env.agent.id, accountID: env.accountA)

        let page = try env.gateway.search("alpha", credential: env.credential)
        #expect(page.items.isEmpty)
    }

    @Test func bodyOffOmitsBodyOnGet() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.allow(
            agentID: env.agent.id,
            accountID: env.accountA,
            placement: "INBOX",
            fields: GrantFields(envelope: true, body: false)
        )

        let message = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountA,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.subject == "Alpha A")
        #expect(message.body == .notGranted)
    }

    @Test func subjectOffOmitsSubjectOnGet() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.allow(
            agentID: env.agent.id,
            accountID: env.accountA,
            placement: "INBOX",
            fields: GrantFields(
                subject: false,
                from: true,
                to: true,
                date: true,
                body: false
            )
        )

        let message = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountA,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.subject == "")
        #expect(!message.from.isEmpty)
        #expect(message.body == .notGranted)
    }

    @Test func legacyEnvelopeJSONExpandsToHeaderFlags() throws {
        let json = Data("""
        {"envelope":false,"body":true,"attachmentMetadata":false,"attachmentContent":false}
        """.utf8)
        let fields = try JSONDecoder().decode(GrantFields.self, from: json)
        #expect(fields.subject == false)
        #expect(fields.from == false)
        #expect(fields.to == false)
        #expect(fields.cc == false)
        #expect(fields.date == false)
        #expect(fields.body == true)
    }

    @Test func ccOffOmitsCcOnGet() throws {
        let env = try GrantFixture()
        defer { env.remove() }

        try env.grants.allow(
            agentID: env.agent.id,
            accountID: env.accountA,
            placement: "INBOX",
            fields: GrantFields(
                subject: true,
                from: true,
                to: true,
                cc: false,
                date: true,
                body: false
            )
        )

        let message = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountA,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.cc == "")
        #expect(!message.to.isEmpty)
    }

    @Test func grantsForAgentADoNotAllowAgentB() throws {
        let grants = GrantGate()
        try grants.allow(agentID: "agent-a", accountID: "acc-a")
        try grants.allow(agentID: "agent-a", accountID: "acc-a", placement: "INBOX")

        #expect(grants.allows(agentID: "agent-a", accountID: "acc-a", placement: "INBOX"))
        #expect(!grants.allows(agentID: "agent-b", accountID: "acc-a", placement: "INBOX"))
        #expect(grants.list(agentID: "agent-b").isEmpty)
        #expect(grants.allGrants().allSatisfy { $0.agentID == "agent-a" })
    }

    @Test func allGrantsReturnsUnionAcrossAgents() throws {
        let grants = GrantGate()
        try grants.allow(agentID: "a", accountID: "acc-a")
        try grants.allow(agentID: "b", accountID: "acc-b")
        #expect(Set(grants.allGrants().map(\.agentID)) == ["a", "b"])
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
            Cc: Carol <carol@example.com>
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
