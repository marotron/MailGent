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
            Cc: Carol <carol@example.com>
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
        #expect(message.cc == "Carol <carol@example.com>")
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

    @Test func searchRanksHeaderMatchesAboveBodyOnlyNoiseAcrossAccounts() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        // Lexicographically earlier account UUID — body-only noise that used to fill page 1.
        let noisy = "0CC9826F-AE36-4353-92A8-F122E726F7B2"
        let relevant = "2D1F6879-5270-4EB9-87A0-5A3D74ECFDCB"

        for i in 1...30 {
            try root.writeEmlx(
                named: "\(i).emlx",
                rfc822: """
                From: Indeed <donotreply@jobalert.indeed.com>
                To: user@example.com
                Subject: Team Member at Shop. 29 more new jobs in b13
                Date: Mon, \(String(format: "%02d", i)) Jul 2026 09:00:00 +0000
                Content-Type: text/plain

                Jobs near birmingham council area listings and more.
                """,
                account: noisy,
                mailbox: "INBOX.mbox"
            )
        }

        try root.writeEmlx(
            named: "100.emlx",
            rfc822: """
            From: Revenues E-Mail Queries <Revenues.e-mail.queries@birmingham.gov.uk>
            To: user@example.com
            Subject: RE: Council Tax Account - Ref: 5064361661
            Date: Tue, 18 Aug 2026 13:23:06 +0000
            Content-Type: text/plain

            Thank you for your enquiry.
            """,
            account: relevant,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        let page = try ReadAPI(index: index).search("birmingham council", limit: 25)
        #expect(page.items.first?.accountID == relevant)
        #expect(page.items.first?.id == "100")
        #expect(page.items.first?.subject.contains("Council Tax Account") == true)
    }

    @Test func searchTreatsFTSOperatorsAsLiteralTokens() throws {
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

        #expect(try index.search("OR").isEmpty)
        #expect(try index.search("from:amazon OR invoice").isEmpty)
        #expect(try index.search("").isEmpty)
        #expect(try index.search("Hello").map(\.id) == ["1"])
        #expect(try index.search("Hello there").map(\.id) == ["1"])
        #expect(try index.search("Hello OR nosuch").isEmpty)
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

    @Test func reopenedIndexReturnsPreviouslyIngestedMessage() throws {
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

        do {
            let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
            #expect(try index.ingest().new == [
                IndexedMessageRef(accountID: accountID, placement: "INBOX", id: "1"),
            ])
        }

        let reopened = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        let message = try reopened.get(accountID: accountID, placement: "INBOX", id: "1")
        #expect(message.subject == "Hello")
        #expect(message.body == "Hi there")

        let page = try ReadAPI(index: reopened).list(limit: 25)
        #expect(page.items.map(\.id) == ["1"])
        #expect(page.items[0].subject == "Hello")
        #expect(page.items[0].accountID == accountID)
        #expect(page.items[0].placement == "INBOX")
    }

    @Test func newIndexOnSameDatabaseIngestsOnlyPlantedArrival() throws {
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

        do {
            let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
            #expect(try index.ingest().new == [
                IndexedMessageRef(accountID: accountID, placement: "INBOX", id: "1"),
            ])
        }

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

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        #expect(try index.ingest().new == [
            IndexedMessageRef(accountID: accountID, placement: "INBOX", id: "2"),
        ])
        #expect(try index.get(accountID: accountID, placement: "INBOX", id: "1").subject == "Hello")
        #expect(try index.search("Hello").map(\.id) == ["1"])
        #expect(try index.search("Follow").map(\.id) == ["2"])
    }

    @Test func ingestProgressReportsMailboxAndMonotonicProcessed() throws {
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
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        nonisolated(unsafe) var reports: [IngestProgress] = []
        _ = try index.ingest { progress in
            reports.append(progress)
        }

        #expect(!reports.isEmpty)
        #expect(reports.allSatisfy { $0.mailboxID == "INBOX" })
        #expect(reports.allSatisfy { $0.accountID == accountID })
        let processed = reports.map(\.processed)
        #expect(processed.first == 1)
        #expect(zip(processed, processed.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func ingestProgressIncludesKnownTotalHintAndIndexingPhase() throws {
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
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        nonisolated(unsafe) var reports: [IngestProgress] = []
        _ = try index.ingest(totalHint: 2) { progress in
            reports.append(progress)
        }

        #expect(!reports.isEmpty)
        #expect(reports.allSatisfy { $0.totalHint == 2 })
        #expect(reports.allSatisfy { $0.phase == .indexing })
    }

    @Test func ingestPersistsLastIngestAtAndNewestMessageDateAcrossReopen() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Older
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            First
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "2.emlx",
            rfc822: """
            From: Carol <carol@example.com>
            To: Bob <bob@example.com>
            Subject: Newer
            Date: Wed, 3 Jan 2024 12:00:00 +0000
            Content-Type: text/plain

            Second
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-index-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: db) }

        let before = Date()
        let freshness: IndexFreshness
        do {
            let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
            #expect(try index.freshness().lastIngestAt == nil)
            #expect(try index.freshness().newestMessageDate == nil)
            _ = try index.ingest()
            freshness = try index.freshness()
        }
        let after = Date()

        #expect(freshness.newestMessageDate == "Wed, 3 Jan 2024 12:00:00 +0000")
        #expect(freshness.indexedCount == 2)
        let stamped = try #require(freshness.lastIngestAt)
        #expect(stamped >= before.addingTimeInterval(-1))
        #expect(stamped <= after.addingTimeInterval(1))

        let reopened = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        let again = try reopened.freshness()
        #expect(again.lastIngestAt == stamped)
        #expect(again.newestMessageDate == "Wed, 3 Jan 2024 12:00:00 +0000")
        #expect(again.indexedCount == 2)
    }
}
