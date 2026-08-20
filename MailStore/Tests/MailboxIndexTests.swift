import Foundation
import MailStore
import Testing

struct MailboxIndexTests {
    @Test func firstIngestMakesMessageRetrievableByAccountAndPlacement() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Hello
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Hi there
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        let ingested = try index.ingest()
        #expect(ingested.new == [
            IndexedMessageRef(accountID: accountID, placement: "INBOX", id: "1"),
        ])

        let message = try index.get(accountID: accountID, placement: "INBOX", id: "1")
        #expect(message.accountID == accountID)
        #expect(message.placement == "INBOX")
        #expect(message.id == "1")
        #expect(message.from == "Alice <alice@example.com>")
        #expect(message.to == "Bob <bob@example.com>")
        #expect(message.date == "Mon, 1 Jan 2024 00:00:00 +0000")
        #expect(message.subject == "Hello")
        #expect(message.body == "Hi there")
        #expect(message.isPartial == false)
    }

    @Test func secondIngestReportsOnlyPlantedNewMessage() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Hello
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Hi there
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        #expect(try index.ingest().new == [
            IndexedMessageRef(accountID: accountID, placement: "INBOX", id: "1"),
        ])
        #expect(try index.ingest().new == [])

        try root.writeEmlx(
            named: "2.emlx",
            rfc822: """
            From: Carol <carol@example.com>
            To: Bob <bob@example.com>
            Subject: Follow up
            Date: Tue, 2 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            New mail
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        #expect(try index.ingest().new == [
            IndexedMessageRef(accountID: accountID, placement: "INBOX", id: "2"),
        ])

        let planted = try index.get(accountID: accountID, placement: "INBOX", id: "2")
        #expect(planted.subject == "Follow up")
        #expect(planted.body == "New mail")
        #expect(try index.get(accountID: accountID, placement: "INBOX", id: "1").subject == "Hello")
    }

    @Test func ingestReindexesMessageWhenFileIdentityChanges() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Hello
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Hi there
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Hello again
            Date: Mon, 1 Jan 2024 12:00:00 +0000
            Content-Type: text/plain

            edited body
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        #expect(try index.ingest().new == [
            IndexedMessageRef(accountID: accountID, placement: "INBOX", id: "1"),
        ])
        let message = try index.get(accountID: accountID, placement: "INBOX", id: "1")
        #expect(message.subject == "Hello again")
        #expect(message.body == "edited body")
    }

    @Test func searchHitsKnownFixtureLiterals() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Hello
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Hi there
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "2.emlx",
            rfc822: """
            From: Carol <carol@example.com>
            To: Bob <bob@example.com>
            Subject: Follow up
            Date: Tue, 2 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            New mail
            """,
            account: accountID,
            mailbox: "Sent Messages.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        let hello = try index.search("Hello")
        #expect(hello.map(\.id) == ["1"])
        #expect(hello[0].accountID == accountID)
        #expect(hello[0].placement == "INBOX")
        #expect(hello[0].subject == "Hello")
        #expect(hello[0].from == "Alice <alice@example.com>")

        let follow = try index.search("Follow")
        #expect(follow.map(\.id) == ["2"])
        #expect(follow[0].placement == "Sent Messages")
        #expect(follow[0].body == "New mail")

        #expect(try index.search("nosuchtoken").isEmpty)
    }

    @Test func ingestSkipsMalformedEmlxAndKeepsReadableNeighbors() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Hello
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Hi there
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        let junk = root.mailboxURL(account: accountID, mailbox: "INBOX.mbox")
            .appendingPathComponent("Messages", isDirectory: true)
            .appendingPathComponent("2.emlx")
        try Data("not-an-emlx".utf8).write(to: junk)

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        #expect(try index.ingest().new == [
            IndexedMessageRef(accountID: accountID, placement: "INBOX", id: "1"),
        ])
        #expect(try index.get(accountID: accountID, placement: "INBOX", id: "1").subject == "Hello")
    }
}
