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
            Subject: Zanzibar one
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Body one
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "2.emlx",
            rfc822: """
            From: Carol <carol@example.com>
            To: Bob <bob@example.com>
            Subject: Zanzibar two
            Date: Tue, 2 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Body two
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
        #expect(first.items.map(\.id) == ["2"])
        #expect(first.items[0].placement == "Sent Messages")
        #expect(first.nextCursor != nil)

        let second = try api.search("Zanzibar", limit: 1, cursor: first.nextCursor)
        #expect(second.items.map(\.id) == ["1"])
        #expect(second.items[0].placement == "INBOX")
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

    @Test func getReturnsDecodedBodyAndRawMIMEBody() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "9.emlx",
            rfc822: """
            From: a@example.com
            To: b@example.com
            Subject: Plain QP
            Date: Sat, 03 Sep 2022 01:31:30 +0000
            Content-Type: text/plain; charset=utf-8
            Content-Transfer-Encoding: quoted-printable

            Caf=C3=A9 au lait
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let message = try ReadAPI(index: index).get(accountID: accountID, placement: "INBOX", id: "9")
        #expect(message.body == .text("Café au lait"))
        #expect(message.rawBody.contains("Caf=C3=A9 au lait"))
    }

    @Test func getReturnsHTMLBodyWhenPresent() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "10.emlx",
            rfc822: """
            From: a@example.com
            To: b@example.com
            Subject: HTML only
            Date: Sat, 4 Apr 2026 09:48:46 +0000
            MIME-Version: 1.0
            Content-Type: multipart/alternative; boundary="b1"

            --b1
            Content-Type: text/html; charset=utf-8
            Content-Transfer-Encoding: quoted-printable

            <p>Hello=20there</p>
            --b1--
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let message = try ReadAPI(index: index).get(accountID: accountID, placement: "INBOX", id: "10")
        #expect(message.htmlBody == "<p>Hello there</p>")
        #expect(message.body == .notAvailable)
    }

    @Test func getIncludesInlineMIMEAttachmentMetadata() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "88.emlx",
            rfc822: """
            From: Me <me@example.com>
            To: Team <team@example.com>
            Subject: Check-in vs check-out
            Date: Sun, 23 Aug 2026 12:00:00 +0000
            MIME-Version: 1.0
            Content-Type: multipart/alternative; boundary="alt"

            --alt
            Content-Type: text/plain; charset=utf-8

            1. Check-in is arrival
            --alt
            Content-Type: multipart/mixed; boundary="mix"

            --mix
            Content-Type: text/html; charset=utf-8

            <p>Hi</p>
            --mix
            Content-Type: application/pdf; name="checkin-vs-checkout-compare.pdf"
            Content-Disposition: inline; filename="checkin-vs-checkout-compare.pdf"
            Content-Transfer-Encoding: base64

            JVBERi0xLjQK
            --mix--
            --alt--
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let message = try ReadAPI(index: index).get(accountID: accountID, placement: "INBOX", id: "88")
        #expect(message.attachments.map(\.filename) == ["checkin-vs-checkout-compare.pdf"])
        #expect(message.attachments.first?.byteCount == 9)
        #expect(message.attachmentMetadataGranted == true)

        let hidden = message.applying(GrantFields(envelope: true, body: true, attachmentMetadata: false))
        #expect(hidden.attachments.isEmpty)
        #expect(hidden.attachmentMetadataGranted == false)
        #expect(hidden.body == .text("1. Check-in is arrival"))

        let shown = message.applying(GrantFields(envelope: true, body: true, attachmentMetadata: true))
        #expect(shown.attachments.map(\.filename) == ["checkin-vs-checkout-compare.pdf"])
        #expect(shown.attachmentMetadataGranted == true)
    }

    @Test func getPrettyHTMLFallsBackWhenHTMLIsPrefixOfPlain() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "88.emlx",
            rfc822: """
            From: Me <me@example.com>
            To: Team <team@example.com>
            Subject: Check-in vs check-out
            Date: Sun, 23 Aug 2026 12:00:00 +0000
            MIME-Version: 1.0
            Content-Type: multipart/alternative; boundary="alt"

            --alt
            Content-Type: text/plain; charset=utf-8

            Hi team,

            Quick compare of check-in vs check-out.

            1. Check-in is arrival
            2. Check-out is departure
            --alt
            Content-Type: text/html; charset=utf-8

            <html><body><p>Hi team,</p><p>Quick compare of check-in vs check-out.</p></html>
            --alt--
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let message = try ReadAPI(index: index).get(accountID: accountID, placement: "INBOX", id: "88")
        #expect(message.prettyHTMLBody == nil)
        #expect(message.body == .text("""
        Hi team,

        Quick compare of check-in vs check-out.

        1. Check-in is arrival
        2. Check-out is departure
        """))
    }

    @Test func listScopesToAccountAndPlacementBeforePaging() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let first = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let second = "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
        for i in 1...3 {
            try root.writeEmlx(
                named: "\(i).emlx",
                rfc822: """
                From: a@example.com
                To: b@example.com
                Subject: First \(i)
                Date: Mon, 1 Jan 2024 00:00:00 +0000
                Content-Type: text/plain

                body \(i)
                """,
                account: first,
                mailbox: "INBOX.mbox"
            )
        }
        try root.writeEmlx(
            named: "9.emlx",
            rfc822: """
            From: a@example.com
            To: b@example.com
            Subject: Second only
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            yahoo body
            """,
            account: second,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()
        let api = ReadAPI(index: index)

        // Global first page would be dominated by `first` if we filtered after LIMIT.
        let page = try api.list(limit: 2, accountID: second, placement: "INBOX")
        #expect(page.items.map(\.id) == ["9"])
        #expect(page.items.map(\.subject) == ["Second only"])
        #expect(page.nextCursor == nil)
    }
}
