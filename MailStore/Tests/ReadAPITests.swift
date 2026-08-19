import Foundation
import MailStore
import Testing

struct ReadAPITests {
    @Test func listPagesWithCursorAndShowsAccountAndPlacement() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: One
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            first
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "2.emlx",
            rfc822: """
            From: Carol <carol@example.com>
            To: Bob <bob@example.com>
            Subject: Two
            Date: Tue, 2 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            second
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "3.emlx",
            rfc822: """
            From: Dan <dan@example.com>
            To: Bob <bob@example.com>
            Subject: Three
            Date: Wed, 3 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            third
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let api = ReadAPI(index: index)

        let first = try api.list(limit: 2)
        #expect(first.items.map(\.id) == ["1", "2"])
        #expect(first.items.map(\.subject) == ["One", "Two"])
        #expect(first.items[0].accountID == accountID)
        #expect(first.items[0].placement == "INBOX")
        #expect(first.nextCursor != nil)

        let second = try api.list(limit: 2, cursor: first.nextCursor)
        #expect(second.items.map(\.id) == ["3"])
        #expect(second.items[0].subject == "Three")
        #expect(second.nextCursor == nil)

        let all = try api.list()
        #expect(all.items.map(\.id) == ["1", "2", "3"])
        #expect(all.nextCursor == nil)
    }

    @Test func listClampsPageSizeToOneHundred() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        for i in 1...101 {
            try root.writeEmlx(
                named: "\(i).emlx",
                rfc822: """
                From: a@example.com
                To: b@example.com
                Subject: M\(i)
                Date: Mon, 1 Jan 2024 00:00:00 +0000
                Content-Type: text/plain

                body \(i)
                """,
                account: accountID,
                mailbox: "INBOX.mbox"
            )
        }

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let page = try ReadAPI(index: index).list(limit: 200)
        #expect(page.items.count == 100)
        #expect(page.nextCursor != nil)
    }

    @Test func searchPagesHitsWithAccountAndPlacement() throws {
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

            Zanzibar one
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

            Zanzibar two
            """,
            account: accountID,
            mailbox: "Sent Messages.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let api = ReadAPI(index: index)

        let first = try api.search("Zanzibar", limit: 1)
        #expect(first.items.map(\.id) == ["1"])
        #expect(first.items[0].placement == "INBOX")
        #expect(first.nextCursor != nil)

        let second = try api.search("Zanzibar", limit: 1, cursor: first.nextCursor)
        #expect(second.items.map(\.id) == ["2"])
        #expect(second.items[0].placement == "Sent Messages")
        #expect(second.nextCursor == nil)
    }

    @Test func listPlacementsReturnsAccountAndMailbox() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: a@example.com
            To: b@example.com
            Subject: Inbox
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Hi
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "2.emlx",
            rfc822: """
            From: a@example.com
            To: b@example.com
            Subject: Sent
            Date: Tue, 2 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Bye
            """,
            account: accountID,
            mailbox: "Sent Messages.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        #expect(try ReadAPI(index: index).listPlacements() == [
            Placement(accountID: accountID, id: "INBOX"),
            Placement(accountID: accountID, id: "Sent Messages"),
        ])
    }

    @Test func getMarksPartialAndLeavesStubBodySearchable() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "7.partial.emlx",
            rfc822: """
            From: a@example.com
            To: b@example.com
            Subject: Partial
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            has stub
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let api = ReadAPI(index: index)

        let hits = try api.search("stub")
        #expect(hits.items.map(\.id) == ["7"])
        #expect(hits.items[0].isPartial == true)

        let message = try api.get(accountID: accountID, placement: "INBOX", id: "7")
        #expect(message.isPartial == true)
        #expect(message.body == .text("has stub"))
        #expect(message.subject == "Partial")
    }

    @Test func getEmptyBodyIsNotAvailable() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "8.emlx",
            rfc822: """
            From: a@example.com
            To: b@example.com
            Subject: Empty
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let message = try ReadAPI(index: index).get(accountID: accountID, placement: "INBOX", id: "8")
        #expect(message.subject == "Empty")
        #expect(message.body == .notAvailable)
        #expect(message.isPartial == false)
    }
}
