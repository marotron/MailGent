import Foundation

/// Reads Apple Mail’s on-disk `.emlx` store from a Mail library root or `V*` folder.
public struct MailStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// UUID account folders under the newest `V*` tree that contain mailbox content.
    public func accounts() throws -> [MailAccount] {
        let versionRoot = try Self.resolveVersionRoot(in: root)
        return try Self.accountFolders(in: versionRoot)
            .map { MailAccount(id: $0.lastPathComponent) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public func mailboxes(in accountID: String) throws -> [Mailbox] {
        let account = try accountURL(id: accountID)
        return try Self.mboxPackages(in: account)
            .map { Mailbox(id: Self.mailboxStem(from: $0.lastPathComponent)) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public func messageIDs(in accountID: String, mailbox mailboxID: String) throws -> [String] {
        let directory = try mailboxURL(accountID: accountID, mailboxID: mailboxID)
        let files = try Self.emlxFiles(under: directory)
        var ids = Set<String>()
        for file in files {
            ids.insert(Self.messageID(from: file.lastPathComponent))
        }
        return ids.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public func message(accountID: String, mailbox mailboxID: String, id: String) throws -> MailMessage {
        let url = try emlxURL(accountID: accountID, mailboxID: mailboxID, id: id)
        let parsedEmlx = try Self.parseEmlx(url)
        let parsed = try Self.parseRFC822(parsedEmlx.data)
        return MailMessage(
            id: id,
            from: parsed.from,
            to: parsed.to,
            date: parsed.date,
            subject: parsed.subject,
            body: parsed.body,
            isPartial: url.lastPathComponent.lowercased().hasSuffix(".partial.emlx"),
            isDraft: Self.isDraftFlag(parsedEmlx.flags),
            attachments: Self.externalAttachmentMetadata(forEmlx: url)
        )
    }

    public func attachmentData(
        accountID: String,
        mailbox mailboxID: String,
        messageID: String,
        filename: String
    ) throws -> Data {
        let url = try emlxURL(accountID: accountID, mailboxID: mailboxID, id: messageID)
        guard let file = Self.externalAttachmentFiles(forEmlx: url).first(where: {
            $0.filename.lowercased() == filename.lowercased()
        }) else {
            throw MailStoreError.attachmentNotFound
        }
        do {
            return try Data(contentsOf: file.url)
        } catch {
            throw MailStoreError.unreadable
        }
    }
}

public struct MailAccount: Equatable, Sendable, Identifiable {
    /// UUID folder name under `Mail/V*`.
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct Mailbox: Equatable, Sendable, Identifiable {
    /// `.mbox` package stem (`INBOX.mbox` → `INBOX`).
    public let id: String

    public init(id: String) {
        self.id = id
    }
}

public struct MailMessage: Equatable, Sendable, Identifiable {
    public let id: String
    public let from: String
    public let to: String
    public let date: String
    public let subject: String
    public let body: String
    public let isPartial: Bool
    public let isDraft: Bool
    public let attachments: [MailAttachment]
}

public struct MailAttachment: Equatable, Sendable {
    public let filename: String
    public let byteCount: Int

    public init(filename: String, byteCount: Int) {
        self.filename = filename
        self.byteCount = byteCount
    }
}

public enum MailStoreError: Error, Equatable {
    case mailLibraryNotFound
    case noVersionFolder
    case unreadable
    case accountNotFound
    case mailboxNotFound
    case messageNotFound
    case malformed
    case attachmentNotFound
}

extension MailStore {
    static func resolveVersionRoot(in mailRoot: URL) throws -> URL {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: mailRoot.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw MailStoreError.mailLibraryNotFound
        }

        if isVersionFolder(mailRoot) {
            return mailRoot
        }

        let versions: [URL]
        do {
            versions = try FileManager.default.contentsOfDirectory(
                at: mailRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            .filter(isVersionFolder)
            .sorted { versionNumber(of: $0) > versionNumber(of: $1) }
        } catch {
            throw MailStoreError.unreadable
        }

        guard let latest = versions.first else {
            throw MailStoreError.noVersionFolder
        }
        return latest
    }

    static func isVersionFolder(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard name.count >= 2, name.first == "V" else { return false }
        return name.dropFirst().allSatisfy(\.isNumber)
    }

    static func versionNumber(of url: URL) -> Int {
        Int(url.lastPathComponent.dropFirst()) ?? 0
    }

    static func accountFolders(in versionRoot: URL) throws -> [URL] {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: versionRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw MailStoreError.unreadable
        }

        return children.filter { url in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  looksLikeAccountID(url.lastPathComponent)
            else { return false }
            return hasMailboxContent(url)
        }
    }

    static func looksLikeAccountID(_ name: String) -> Bool {
        let parts = name.split(separator: "-")
        guard parts.count == 5 else { return false }
        let lengths = [8, 4, 4, 4, 12]
        for (part, length) in zip(parts, lengths) {
            guard part.count == length, part.allSatisfy(\.isHexDigit) else { return false }
        }
        return true
    }

    static func hasMailboxContent(_ accountURL: URL) -> Bool {
        guard let enumerator = FileManager.default.enumerator(
            at: accountURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        var depth = 0
        for case let item as URL in enumerator {
            depth += 1
            if depth > 200 { break }
            let name = item.lastPathComponent.lowercased()
            if name.hasSuffix(".mbox") || name.hasSuffix(".emlx") || name.hasSuffix(".partial.emlx") {
                return true
            }
            if name == "messages" || name == "table_of_contents" {
                return true
            }
        }
        return false
    }

    func accountURL(id: String) throws -> URL {
        let versionRoot = try Self.resolveVersionRoot(in: root)
        let url = versionRoot.appendingPathComponent(id, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw MailStoreError.accountNotFound
        }
        return url
    }

    func mailboxURL(accountID: String, mailboxID: String) throws -> URL {
        let account = try accountURL(id: accountID)
        let url = account.appendingPathComponent("\(mailboxID).mbox", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw MailStoreError.mailboxNotFound
        }
        return url
    }

    static func mboxPackages(in accountURL: URL) throws -> [URL] {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: accountURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw MailStoreError.unreadable
        }
        return children.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                && isDirectory.boolValue
                && url.pathExtension.lowercased() == "mbox"
        }
    }

    static func emlxFiles(under root: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw MailStoreError.unreadable
        }
        var files: [URL] = []
        for case let item as URL in enumerator {
            if isEmlxFile(item) {
                files.append(item)
            }
        }
        return files
    }

    static func isEmlxFile(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return name.hasSuffix(".emlx") && !name.hasSuffix(".emlxpart")
    }

    static func messageID(from filename: String) -> String {
        let lower = filename.lowercased()
        if lower.hasSuffix(".partial.emlx") {
            return String(filename.dropLast(".partial.emlx".count))
        }
        if lower.hasSuffix(".emlx") {
            return String(filename.dropLast(".emlx".count))
        }
        return filename
    }

    static func mailboxStem(from lastPathComponent: String) -> String {
        let name = lastPathComponent as NSString
        if name.pathExtension.lowercased() == "mbox" {
            return name.deletingPathExtension
        }
        return lastPathComponent
    }

    func emlxURL(accountID: String, mailboxID: String, id: String) throws -> URL {
        let directory = try mailboxURL(accountID: accountID, mailboxID: mailboxID)
        let files = try Self.emlxFiles(under: directory).filter {
            Self.messageID(from: $0.lastPathComponent) == id
        }
        if let partial = files.first(where: { $0.lastPathComponent.lowercased().hasSuffix(".partial.emlx") }) {
            return partial
        }
        if let file = files.first {
            return file
        }
        throw MailStoreError.messageNotFound
    }

    static func parseEmlx(_ url: URL) throws -> (data: Data, flags: Int?) {
        let fileData: Data
        do {
            fileData = try Data(contentsOf: url)
        } catch {
            throw MailStoreError.unreadable
        }
        guard !fileData.isEmpty, let newline = fileData.firstIndex(of: UInt8(ascii: "\n")) else {
            throw MailStoreError.malformed
        }
        let countBytes = fileData[..<newline]
        guard let countString = String(data: Data(countBytes), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              let byteCount = Int(countString),
              byteCount >= 0
        else {
            throw MailStoreError.malformed
        }
        let start = fileData.index(after: newline)
        guard byteCount <= fileData.distance(from: start, to: fileData.endIndex) else {
            throw MailStoreError.malformed
        }
        let end = fileData.index(start, offsetBy: byteCount)
        let payload = Data(fileData[start..<end])
        let flags = appleMailFlags(fromTrailing: Data(fileData[end...]))
        return (payload, flags)
    }

    /// Apple Mail draft flag (bit 4). Proven by ArchMail fixtures; other bits are not named.
    static let draftFlagMask = 0x10

    static func isDraftFlag(_ flags: Int?) -> Bool {
        guard let flags else { return false }
        return (flags & draftFlagMask) != 0
    }

    static func appleMailFlags(fromTrailing trailing: Data) -> Int? {
        guard !trailing.isEmpty else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: trailing,
            options: [],
            format: nil
        ) as? [String: Any] else { return nil }
        if let flags = plist["flags"] as? Int { return flags }
        if let flags = plist["flags"] as? NSNumber { return flags.intValue }
        return nil
    }

    static func parseRFC822(_ data: Data) throws -> (from: String, to: String, date: String, subject: String, body: String) {
        guard !data.isEmpty else { throw MailStoreError.malformed }
        let text = String(decoding: data, as: UTF8.self)
        let (headerBlock, bodyBlock) = splitHeadersAndBody(text)
        let headers = parseHeaders(headerBlock)
        return (
            from: headers["from"] ?? "",
            to: headers["to"] ?? "",
            date: headers["date"] ?? "",
            subject: headers["subject"] ?? "",
            body: bodyBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func splitHeadersAndBody(_ text: String) -> (String, String) {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        if let range = normalized.range(of: "\n\n") {
            return (String(normalized[..<range.lowerBound]), String(normalized[range.upperBound...]))
        }
        return (normalized, "")
    }

    static func parseHeaders(_ headerBlock: String) -> [String: String] {
        var headers: [String: String] = [:]
        var currentName: String?
        var currentValue = ""
        let lines = headerBlock.replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)

        func flush() {
            guard let name = currentName else { return }
            headers[name] = currentValue.trimmingCharacters(in: .whitespaces)
        }

        for line in lines {
            if line.first?.isWhitespace == true, currentName != nil {
                currentValue += " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            flush()
            if let colon = line.firstIndex(of: ":") {
                currentName = line[..<colon].lowercased()
                currentValue = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            } else {
                currentName = nil
                currentValue = ""
            }
        }
        flush()
        return headers
    }

    static func externalAttachmentMetadata(forEmlx url: URL) -> [MailAttachment] {
        externalAttachmentFiles(forEmlx: url).map {
            MailAttachment(filename: $0.filename, byteCount: $0.byteCount)
        }
    }

    static func externalAttachmentFiles(forEmlx url: URL) -> [(filename: String, url: URL, byteCount: Int)] {
        let id = messageID(from: url.lastPathComponent)
        let parent = url.deletingLastPathComponent()
        var candidates: [URL] = [
            parent.appendingPathComponent("Attachments", isDirectory: true)
                .appendingPathComponent(id, isDirectory: true),
        ]
        if parent.lastPathComponent == "Messages" {
            candidates.append(
                parent
                    .deletingLastPathComponent()
                    .appendingPathComponent("Attachments", isDirectory: true)
                    .appendingPathComponent(id, isDirectory: true)
            )
        }

        var collected: [(filename: String, url: URL, byteCount: Int)] = []
        var seen = Set<String>()
        for dir in candidates {
            for file in filesRecursively(in: dir) {
                let name = file.lastPathComponent
                if name.hasPrefix("._") || name == ".DS_Store" { continue }
                let key = name.lowercased()
                guard !seen.contains(key) else { continue }
                let values = try? file.resourceValues(forKeys: [.fileSizeKey])
                let byteCount = values?.fileSize ?? 0
                guard byteCount > 0 else { continue }
                seen.insert(key)
                collected.append((filename: name, url: file, byteCount: byteCount))
            }
        }
        return collected
    }

    static func filesRecursively(in directory: URL) -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              )
        else { return [] }

        var files: [URL] = []
        for case let item as URL in enumerator {
            let values = try? item.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                files.append(item)
            }
        }
        return files
    }
}
