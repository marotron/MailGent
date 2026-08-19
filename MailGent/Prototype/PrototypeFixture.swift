import Foundation

/// Known-good `.emlx` tree for the companion-read prototype. Wipe with the session.
enum PrototypeAccounts {
    static let work = "11111111-1111-1111-1111-111111111111"
    static let personal = "22222222-2222-2222-2222-222222222222"

    static func label(_ accountID: String) -> String {
        switch accountID {
        case work: "Work Gmail"
        case personal: "Personal"
        default: String(accountID.prefix(8))
        }
    }
}

enum PrototypeFixture {
    static func plant(at root: URL) throws {
        try write(
            named: "1.emlx",
            rfc822: """
            From: Ava Chen <ava@company.com>
            To: you@company.com
            Subject: Q3 planning notes
            Date: Mon, 19 Aug 2024 10:32:00 +0000
            Content-Type: text/plain

            Here is the revised schedule and proposed next steps for quarterly planning.
            """,
            account: PrototypeAccounts.work,
            mailbox: "INBOX.mbox",
            root: root
        )
        try write(
            named: "2.emlx",
            rfc822: """
            From: Product team <product@company.com>
            To: you@company.com
            Subject: Planning workshop follow-up
            Date: Fri, 16 Aug 2024 16:05:00 +0000
            Content-Type: text/plain

            Thanks for joining. Notes and actions from the planning workshop are attached.
            """,
            account: PrototypeAccounts.work,
            mailbox: "INBOX.mbox",
            root: root
        )
        try write(
            named: "3.emlx",
            rfc822: """
            From: you@company.com
            To: Ava Chen <ava@company.com>
            Subject: Re: Q3 planning notes
            Date: Mon, 19 Aug 2024 11:04:00 +0000
            Content-Type: text/plain

            Confirmed for Tuesday. I will send the planning deck before noon.
            """,
            account: PrototypeAccounts.work,
            mailbox: "Sent Messages.mbox",
            root: root
        )
        try write(
            named: "4.emlx",
            rfc822: """
            From: Marcus Ltd. <statements@marcus.example>
            To: you@personal.example
            Subject: Quarterly statement ready
            Date: Sun, 18 Aug 2024 09:12:00 +0000
            Content-Type: text/plain

            Your new statement is ready to review in the portal.
            """,
            account: PrototypeAccounts.personal,
            mailbox: "INBOX.mbox",
            root: root
        )
        try write(
            named: "7.partial.emlx",
            rfc822: """
            From: Photos <photos@personal.example>
            To: you@personal.example
            Subject: Download remaining
            Date: Sat, 17 Aug 2024 14:20:00 +0000
            Content-Type: text/plain

            has stub
            """,
            account: PrototypeAccounts.personal,
            mailbox: "INBOX.mbox",
            root: root
        )
        try write(
            named: "8.emlx",
            rfc822: """
            From: Receipts <receipts@personal.example>
            To: you@personal.example
            Subject: Empty receipt
            Date: Thu, 15 Aug 2024 08:00:00 +0000
            Content-Type: text/plain

            """,
            account: PrototypeAccounts.personal,
            mailbox: "Archive.mbox",
            root: root
        )
    }

    private static func write(
        named name: String,
        rfc822: String,
        account: String,
        mailbox: String,
        root: URL
    ) throws {
        let messages = root
            .appendingPathComponent("V10", isDirectory: true)
            .appendingPathComponent(account, isDirectory: true)
            .appendingPathComponent(mailbox, isDirectory: true)
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
        	<integer>0</integer>
        </dict>
        </plist>
        """.utf8))
        try file.write(to: messages.appendingPathComponent(name))
    }
}
