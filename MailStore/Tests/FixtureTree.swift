import Foundation

struct FixtureTree {
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
        var url = self.version(version).appendingPathComponent(account, isDirectory: true)
        for part in mailbox.split(separator: "/").map(String.init) {
            url.appendPathComponent(part, isDirectory: true)
        }
        return url
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

    func writeEmlxV10(
        named name: String,
        rfc822: String,
        flags: Int = 0,
        account: String,
        mailbox: String,
        storeID: String = "11111111-2222-3333-4444-555555555555",
        version: String = "V10"
    ) throws {
        let messages = mailboxURL(account: account, version: version, mailbox: mailbox)
            .appendingPathComponent(storeID, isDirectory: true)
            .appendingPathComponent("Data/Messages", isDirectory: true)
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

    func writeEmlxV10Sharded(
        named name: String,
        rfc822: String,
        shard: String,
        flags: Int = 0,
        account: String,
        mailbox: String,
        version: String = "V10"
    ) throws {
        let messages = mailboxURL(account: account, version: version, mailbox: mailbox)
            .appendingPathComponent("Data", isDirectory: true)
        var url = messages
        for part in shard.split(separator: "/").map(String.init) {
            url.appendPathComponent(part, isDirectory: true)
        }
        url.appendPathComponent("Messages", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
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
        try file.write(to: url.appendingPathComponent(name))
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
