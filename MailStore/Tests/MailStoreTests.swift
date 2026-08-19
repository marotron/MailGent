import Foundation
import MailStore
import Testing

struct MailStoreTests {
    @Test func listsAccountFoldersUnderNewestVersionTree() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let oldID = "11111111-2222-3333-4444-555555555555"
        let liveID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let emptyID = "00000000-0000-0000-0000-000000000000"

        try root.makeAccount(id: oldID, version: "V8", mailbox: "Old.mbox")
        try root.makeAccount(id: liveID, version: "V10", mailbox: "INBOX.mbox")
        try FileManager.default.createDirectory(
            at: root.version("V10").appendingPathComponent(emptyID, isDirectory: true),
            withIntermediateDirectories: true
        )

        let store = MailStore(root: root.mail)
        let accounts = try store.accounts()

        #expect(accounts.map(\.id) == [liveID])
    }

    @Test func listsMailboxesAndMessageIDsInAnAccount() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: "From: a@example.com\nTo: b@example.com\nSubject: Inbox\n\nHi\n",
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "2.emlx",
            rfc822: "From: a@example.com\nTo: b@example.com\nSubject: Sent\n\nBye\n",
            account: accountID,
            mailbox: "Sent Messages.mbox"
        )

        let store = MailStore(root: root.mail)
        let mailboxes = try store.mailboxes(in: accountID)
        #expect(mailboxes.map(\.id) == ["INBOX", "Sent Messages"])

        #expect(try store.messageIDs(in: accountID, mailbox: "INBOX") == ["1"])
        #expect(try store.messageIDs(in: accountID, mailbox: "Sent Messages") == ["2"])
    }

    @Test func parsesFullEmlxHeadersAndBody() throws {
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

        let store = MailStore(root: root.mail)
        let message = try store.message(accountID: accountID, mailbox: "INBOX", id: "1")

        #expect(message.id == "1")
        #expect(message.from == "Alice <alice@example.com>")
        #expect(message.to == "Bob <bob@example.com>")
        #expect(message.subject == "Hello")
        #expect(message.body == "Hi there")
        #expect(message.isPartial == false)
        #expect(message.isDraft == false)
    }

    @Test func prefersPartialEmlxAndMarksIncomplete() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "7.emlx",
            rfc822: """
            From: a@example.com
            To: b@example.com
            Subject: Plain
            Content-Type: text/plain

            no files
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "7.partial.emlx",
            rfc822: """
            From: a@example.com
            To: b@example.com
            Subject: Partial
            Content-Type: text/plain

            has stub
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let store = MailStore(root: root.mail)
        #expect(try store.messageIDs(in: accountID, mailbox: "INBOX") == ["7"])

        let message = try store.message(accountID: accountID, mailbox: "INBOX", id: "7")
        #expect(message.subject == "Partial")
        #expect(message.body == "has stub")
        #expect(message.isPartial == true)
        #expect(message.isDraft == false)
    }

    @Test func readsDraftFlagFromEmlxPlist() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "9.emlx",
            rfc822: """
            From: Me <me@example.com>
            To: Me <me@example.com>
            Subject: WIP
            Content-Type: text/plain

            unfinished
            """,
            flags: 0x10,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let store = MailStore(root: root.mail)
        let message = try store.message(accountID: accountID, mailbox: "INBOX", id: "9")
        #expect(message.isDraft == true)
        #expect(message.subject == "WIP")
        #expect(message.body == "unfinished")
    }

    @Test func listsExternalAttachmentMetadataAndFetchesBytesOnDemand() throws {
        let root = try FixtureTree()
        defer { root.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "42.partial.emlx",
            rfc822: """
            From: David Flint <david@example.com>
            To: Marek <marek@example.com>
            Subject: Re: Clarification on updated terms
            MIME-Version: 1.0
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            Content-Type: text/plain; charset=utf-8

            See attached archive.

            --MIX
            Content-Type: application/zip; name="docs.zip"
            Content-Disposition: attachment; filename="docs.zip"
            X-Apple-Content-Length: 12
            Content-Transfer-Encoding: base64


            --MIX--
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )
        try root.writeAttachment(
            messageID: "42",
            relativePath: "2/docs.zip",
            data: Data("ZIP-PAYLOAD!!".utf8),
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let store = MailStore(root: root.mail)
        let message = try store.message(accountID: accountID, mailbox: "INBOX", id: "42")
        #expect(message.isPartial == true)
        #expect(message.attachments == [
            MailAttachment(filename: "docs.zip", byteCount: 13),
        ])

        let bytes = try store.attachmentData(
            accountID: accountID,
            mailbox: "INBOX",
            messageID: "42",
            filename: "docs.zip"
        )
        #expect(String(data: bytes, encoding: .utf8) == "ZIP-PAYLOAD!!")
    }
}

private struct FixtureTree {
    let root: URL

    var mail: URL {
        root.appendingPathComponent("Mail", isDirectory: true)
    }

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-store-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func version(_ name: String) -> URL {
        mail.appendingPathComponent(name, isDirectory: true)
    }

    func makeAccount(id: String, version: String, mailbox: String) throws {
        let mbox = mailboxURL(account: id, version: version, mailbox: mailbox)
        try FileManager.default.createDirectory(at: mbox, withIntermediateDirectories: true)
        try Data("placeholder".utf8).write(to: mbox.appendingPathComponent("table_of_contents"))
    }

    func mailboxURL(account: String, version: String = "V10", mailbox: String) -> URL {
        self.version(version)
            .appendingPathComponent(account, isDirectory: true)
            .appendingPathComponent(mailbox, isDirectory: true)
    }

    func writeEmlx(
        named name: String,
        rfc822: String,
        flags: Int = 0,
        account: String,
        mailbox: String,
        version: String = "V10"
    ) throws {
        let messages = mailboxURL(account: account, version: version, mailbox: mailbox)
            .appendingPathComponent("Messages", isDirectory: true)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)
        let payload = Data(rfc822.utf8)
        var file = Data()
        file.append(Data("\(payload.count)\n".utf8))
        file.append(payload)
        file.append(Data("""

        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        	<key>flags</key>
        	<integer>\(flags)</integer>
        </dict>
        </plist>
        """.utf8))
        try file.write(to: messages.appendingPathComponent(name))
    }

    func writeAttachment(
        messageID: String,
        relativePath: String,
        data: Data,
        account: String,
        mailbox: String,
        version: String = "V10"
    ) throws {
        let file = mailboxURL(account: account, version: version, mailbox: mailbox)
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(messageID, isDirectory: true)
            .appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file)
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
