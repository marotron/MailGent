import Foundation
import MailStore
import SQLite3
import Testing

struct ListAccountsTests {
    @Test func omitsEmptyPlacementAccountsByDefault() throws {
        let env = try ListAccountsFixture(grantAccountA: true, grantAccountB: false)
        defer { env.remove() }

        let accounts = try env.gateway.listAccounts(credential: env.credential)
        #expect(accounts.map(\.accountID) == [env.accountA])
        #expect(accounts[0].placements.sorted() == ["Archive", "INBOX"])
        #expect(accounts[0].email == env.emailA)
        #expect(accounts[0].displayName == env.displayNameA)
    }

    @Test func includesEmptyPlacementAccountsWhenRequested() throws {
        let env = try ListAccountsFixture(grantAccountA: true, grantAccountB: false)
        defer { env.remove() }

        let accounts = try env.gateway.listAccounts(
            credential: env.credential,
            includeEmptyPlacements: true
        )
        #expect(Set(accounts.map(\.accountID)) == Set([env.accountA, env.accountB]))
        #expect(accounts.map(\.displayName) == [env.displayNameA, env.displayNameB].sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        })

        let byID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.accountID, $0) })
        #expect(byID[env.accountA]?.placements.sorted() == ["Archive", "INBOX"])
        #expect(byID[env.accountB]?.placements == [])
        #expect(byID[env.accountB]?.email == env.emailB)
        #expect(byID[env.accountB]?.displayName == env.displayNameB)
    }

    @Test func denyCarveOutRemovesPlacementFromNestedList() throws {
        let env = try ListAccountsFixture(grantAccountA: true, grantAccountB: false)
        defer { env.remove() }

        try env.grants.deny(
            agentID: env.agent.id,
            accountID: env.accountA,
            placement: "Archive"
        )

        let accounts = try env.gateway.listAccounts(credential: env.credential)
        let a = accounts.first { $0.accountID == env.accountA }!
        #expect(a.placements == ["INBOX"])
    }

    @Test func auditsAsListAccounts() throws {
        let env = try ListAccountsFixture(grantAccountA: true, grantAccountB: false)
        defer { env.remove() }

        _ = try env.gateway.listAccounts(credential: env.credential)
        let entry = env.audit.entries().last!
        #expect(entry.kind == .listAccounts)
        let payload = try JSONSerialization.jsonObject(
            with: Data(entry.responseSummary.utf8)
        ) as? [String: Any]
        let accounts = payload?["accounts"] as? [[String: Any]]
        #expect(accounts?.count == 1)
        #expect(entry.placements.count == 2)
    }

    @Test func auditsIncludeEmptyPlacementAccountsWhenRequested() throws {
        let env = try ListAccountsFixture(grantAccountA: true, grantAccountB: false)
        defer { env.remove() }

        _ = try env.gateway.listAccounts(
            credential: env.credential,
            includeEmptyPlacements: true
        )
        let entry = env.audit.entries().last!
        #expect(entry.kind == .listAccounts)
        let payload = try JSONSerialization.jsonObject(
            with: Data(entry.responseSummary.utf8)
        ) as? [String: Any]
        let accounts = payload?["accounts"] as? [[String: Any]]
        #expect(accounts?.count == 2)
        #expect(entry.placements.count == 2)
    }
}

private struct ListAccountsFixture {
    let root: FixtureTree
    let db: URL
    let accountsDB: URL
    let credential = "secret-token"
    let accountA = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    let accountB = "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
    let emailA = "marotron@gmail.com"
    let emailB = "nite.ma.roux@gmail.com"
    let displayNameA = "Maro - gmail"
    let displayNameB = "MaRoux - gmail"
    let agent: PairedAgent
    let grants: GrantGate
    let audit: AuditLog
    let gateway: AgentReadAPI

    init(grantAccountA: Bool, grantAccountB: Bool) throws {
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

        accountsDB = try Self.writeAccountsDatabase([
            (id: accountA, displayName: displayNameA, email: emailA),
            (id: accountB, displayName: displayNameB, email: emailB),
        ])

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-list-accounts-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        audit = AuditLog()
        let pairing = Pairing(audit: audit)
        agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        grants = GrantGate()
        if grantAccountA {
            try grants.allow(agentID: agent.id, accountID: accountA)
        }
        if grantAccountB {
            try grants.allow(agentID: agent.id, accountID: accountB)
        }
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            audit: audit,
            accountsDatabases: [accountsDB]
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
        try? FileManager.default.removeItem(at: accountsDB)
    }

    private static func writeAccountsDatabase(
        _ rows: [(id: String, displayName: String, email: String)]
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Accounts-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "ListAccountsTests", code: 1)
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(
            db,
            """
            CREATE TABLE ZACCOUNT (
              ZIDENTIFIER TEXT,
              ZACCOUNTDESCRIPTION TEXT,
              ZUSERNAME TEXT
            );
            """,
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw NSError(domain: "ListAccountsTests", code: 2)
        }
        for row in rows {
            let sql = """
            INSERT INTO ZACCOUNT (ZIDENTIFIER, ZACCOUNTDESCRIPTION, ZUSERNAME)
            VALUES ('\(row.id)', '\(row.displayName)', '\(row.email)');
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "ListAccountsTests", code: 3)
            }
        }
        return url
    }
}
