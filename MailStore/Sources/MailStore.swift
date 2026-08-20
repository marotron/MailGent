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
            .map { Mailbox(id: Self.mailboxID(for: $0, in: account)) }
            .sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    public func messageIDs(in accountID: String, mailbox mailboxID: String) throws -> [String] {
        try emlxEntries(in: accountID, mailbox: mailboxID).map(\.id)
    }

    public func messageCount(in accountID: String, mailbox mailboxID: String) throws -> Int {
        try emlxEntries(in: accountID, mailbox: mailboxID).count
    }

    public func emlxEntries(in accountID: String, mailbox mailboxID: String) throws -> [EmlxEntry] {
        let directory = try mailboxURL(accountID: accountID, mailboxID: mailboxID)
        return try Self.emlxEntries(under: directory)
    }

    public func message(accountID: String, mailbox mailboxID: String, id: String) throws -> MailMessage {
        let url = try emlxURL(accountID: accountID, mailboxID: mailboxID, id: id)
        return try message(at: url)
    }

    public func message(at url: URL) throws -> MailMessage {
        let parsedEmlx = try Self.parseEmlx(url)
        let parsed = try Self.parseRFC822(parsedEmlx.data)
        let id = Self.messageID(from: url.lastPathComponent)
        return MailMessage(
            id: id,
            from: parsed.from,
            to: parsed.to,
            date: parsed.date,
            subject: parsed.subject,
            body: parsed.body,
            rawBody: parsed.rawBody,
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

public struct EmlxEntry: Equatable, Sendable {
    public let id: String
    public let url: URL

    public init(id: String, url: URL) {
        self.id = id
        self.url = url
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
    /// Decoded display body (text/plain preferred; QP/base64 applied).
    public let body: String
    /// Original MIME body block after headers (before transfer-decoding).
    public let rawBody: String
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

private extension MailStore {
    /// Cap indexed body size so one HTML megamail cannot blow the RSS during ingest.
    static let maxIndexedBodyBytes = 32_768
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
        let children = (try? FileManager.default.contentsOfDirectory(
            at: accountURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for child in children {
            if isMailboxPackage(child) {
                return true
            }
        }

        guard let enumerator = FileManager.default.enumerator(
            at: accountURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return false }

        for case let item as URL in enumerator {
            if isMailboxPackage(item) {
                return true
            }
            if isEmlxFile(item) {
                return true
            }
            if item.lastPathComponent == "table_of_contents" {
                return true
            }
            if item.lastPathComponent.lowercased() == "data" {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
                   isDirectory.boolValue
                {
                    enumerator.skipDescendants()
                }
            }
        }
        return false
    }

    static func isMailboxPackage(_ url: URL) -> Bool {
        switch url.pathExtension.lowercased() {
        case "mbox", "imapmbox": true
        default: false
        }
    }

    static func messagesScanRoots(in mbox: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: mbox,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let mboxPath = mbox.standardizedFileURL.path
        var roots: [URL] = []
        for case let item as URL in enumerator {
            if isMailboxPackage(item), item.standardizedFileURL.path != mboxPath {
                enumerator.skipDescendants()
                continue
            }
            guard item.lastPathComponent == "Messages" else { continue }
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                roots.append(item)
            }
        }
        return roots
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
        var url = account
        for part in mailboxID.split(separator: "/").map(String.init) {
            url = try Self.resolveMailboxPackage(named: part, under: url)
        }
        return url
    }

    static func resolveMailboxPackage(named stem: String, under parent: URL) throws -> URL {
        for ext in ["mbox", "imapmbox"] {
            let candidate = parent.appendingPathComponent("\(stem).\(ext)", isDirectory: true)
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue
            {
                return candidate
            }
        }
        throw MailStoreError.mailboxNotFound
    }

    static func mailboxID(for package: URL, in accountURL: URL) -> String {
        let accountParts = accountURL.standardizedFileURL.pathComponents
        let packageParts = package.standardizedFileURL.pathComponents
        guard packageParts.starts(with: accountParts) else {
            return mailboxStem(from: package.lastPathComponent)
        }
        return packageParts
            .dropFirst(accountParts.count)
            .map { mailboxStem(from: $0) }
            .joined(separator: "/")
    }

    static func mboxPackages(in accountURL: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: accountURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            throw MailStoreError.unreadable
        }
        var packages: [URL] = []
        for case let item as URL in enumerator {
            guard isMailboxPackage(item) else { continue }
            if hasDirectMessageContent(item) {
                packages.append(item)
            }
        }
        return packages
    }

    static func hasDirectMessageContent(_ mbox: URL) -> Bool {
        if !messagesScanRoots(in: mbox).isEmpty {
            return true
        }
        if FileManager.default.fileExists(atPath: mbox.appendingPathComponent("table_of_contents").path) {
            return true
        }
        let children = (try? FileManager.default.contentsOfDirectory(
            at: mbox,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return children.contains { isEmlxFile($0) }
    }

    static func emlxFiles(under mbox: URL) throws -> [URL] {
        var files: [URL] = []
        try collectEmlxURLs(into: &files, under: mbox)
        return files
    }

    static func collectEmlxURLs(into files: inout [URL], under mbox: URL) throws {
        let roots = messagesScanRoots(in: mbox)
        let scanRoots = roots.isEmpty ? [mbox] : roots
        for scanRoot in scanRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: scanRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                if roots.isEmpty {
                    throw MailStoreError.unreadable
                }
                continue
            }
            for case let item as URL in enumerator {
                if isMailboxPackage(item) {
                    enumerator.skipDescendants()
                    continue
                }
                if isEmlxFile(item) {
                    files.append(item)
                }
            }
        }
    }

    static func collectEmlxEntries(into byID: inout [String: URL], under mbox: URL) throws {
        let roots = messagesScanRoots(in: mbox)
        let scanRoots = roots.isEmpty ? [mbox] : roots
        for scanRoot in scanRoots {
            guard let enumerator = FileManager.default.enumerator(
                at: scanRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                if roots.isEmpty {
                    throw MailStoreError.unreadable
                }
                continue
            }
            for case let item as URL in enumerator {
                if isMailboxPackage(item) {
                    enumerator.skipDescendants()
                    continue
                }
                guard isEmlxFile(item) else { continue }
                let id = messageID(from: item.lastPathComponent)
                if item.lastPathComponent.lowercased().hasSuffix(".partial.emlx") {
                    byID[id] = item
                } else if byID[id] == nil {
                    byID[id] = item
                }
            }
        }
    }

    static func forEachEmlxEntry(under mbox: URL, _ body: (EmlxEntry) throws -> Void) throws {
        var byID: [String: URL] = [:]
        try collectEmlxEntries(into: &byID, under: mbox)
        for id in byID.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            guard let url = byID[id] else { continue }
            try body(EmlxEntry(id: id, url: url))
        }
    }

    static func emlxEntries(under mbox: URL) throws -> [EmlxEntry] {
        var entries: [EmlxEntry] = []
        try forEachEmlxEntry(under: mbox) { entry in
            entries.append(entry)
        }
        return entries
    }

    static func countEmlxFiles(under mbox: URL) throws -> Int {
        var byID: [String: URL] = [:]
        try collectEmlxEntries(into: &byID, under: mbox)
        return byID.count
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
        switch name.pathExtension.lowercased() {
        case "mbox", "imapmbox":
            return name.deletingPathExtension
        default:
            return lastPathComponent
        }
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

    static func parseRFC822(_ data: Data) throws -> (
        from: String,
        to: String,
        date: String,
        subject: String,
        body: String,
        rawBody: String
    ) {
        guard !data.isEmpty else { throw MailStoreError.malformed }
        let scan = data.prefix(min(data.count, 256_000))
        let text = String(decoding: scan, as: UTF8.self)
        let (headerBlock, bodyBlock) = splitHeadersAndBody(text)
        let headers = parseHeaders(headerBlock)
        let rawBody = bodyBlock
        var body = decodeDisplayBody(bodyBlock: bodyBlock, headers: headers)
        if body.utf8.count > maxIndexedBodyBytes {
            body = String(body.prefix(maxIndexedBodyBytes))
        }
        return (
            from: decodeRFC2047(headers["from"] ?? ""),
            to: decodeRFC2047(headers["to"] ?? ""),
            date: headers["date"] ?? "",
            subject: decodeRFC2047(headers["subject"] ?? ""),
            body: body,
            rawBody: rawBody
        )
    }

    /// Prefer first `text/plain` part; apply Content-Transfer-Encoding.
    static func decodeDisplayBody(bodyBlock: String, headers: [String: String]) -> String {
        let contentType = headers["content-type"] ?? "text/plain"
        if contentType.lowercased().hasPrefix("multipart/") {
            guard let boundary = extractParameter(contentType, named: "boundary") else {
                return bodyBlock.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return firstPlainText(fromMultipart: bodyBlock, boundary: boundary)
                ?? bodyBlock.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let transfer = headers["content-transfer-encoding"]
        let charset = extractParameter(contentType, named: "charset") ?? "utf-8"
        return decodeTransferEncodedBody(bodyBlock, transferEncoding: transfer, charset: charset)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func firstPlainText(fromMultipart body: String, boundary: String) -> String? {
        for part in splitMultipart(body, boundary: boundary) {
            let (partHeaders, partBody) = splitHeadersAndBody(part)
            let headers = parseHeaders(partHeaders)
            let contentType = headers["content-type"] ?? "text/plain"
            if contentType.lowercased().hasPrefix("multipart/") {
                if let nested = extractParameter(contentType, named: "boundary"),
                   let found = firstPlainText(fromMultipart: partBody, boundary: nested)
                {
                    return found
                }
                continue
            }
            guard contentType.lowercased().hasPrefix("text/plain") else { continue }
            let charset = extractParameter(contentType, named: "charset") ?? "utf-8"
            return decodeTransferEncodedBody(
                partBody,
                transferEncoding: headers["content-transfer-encoding"],
                charset: charset
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    static func splitMultipart(_ body: String, boundary: String) -> [String] {
        let normalized = body.replacingOccurrences(of: "\r\n", with: "\n")
        let delimiter = "--" + boundary
        var parts: [String] = []
        for chunk in normalized.components(separatedBy: delimiter) {
            var part = chunk
            if part.hasPrefix("--") { continue }
            if part.hasPrefix("\n") { part.removeFirst() }
            if part.hasSuffix("\n") { part.removeLast() }
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed == "--" { continue }
            if part.hasSuffix("--") {
                part = String(part.dropLast(2))
            }
            parts.append(part.trimmingCharacters(in: CharacterSet(charactersIn: "\n")))
        }
        return parts
    }

    static func extractParameter(_ headerValue: String, named name: String) -> String? {
        for part in headerValue.split(separator: ";").dropFirst() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            guard key == name.lowercased() else { continue }
            var value = trimmed[trimmed.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return String(value)
        }
        return nil
    }

    static func decodeTransferEncodedBody(
        _ body: String,
        transferEncoding: String?,
        charset: String
    ) -> String {
        let encoding = (transferEncoding ?? "7bit").lowercased().trimmingCharacters(in: .whitespaces)
        let data: Data
        switch encoding {
        case "base64":
            let cleaned = body.filter { !$0.isWhitespace }
            data = Data(base64Encoded: cleaned) ?? Data()
        case "quoted-printable":
            data = decodeQuotedPrintableBytes(body)
        default:
            data = Data(body.utf8)
        }
        return decodeRFC2047Bytes(data, charset: charset)
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

/// RFC 2047 encoded-word: `=?charset?Q?text?=` or `=?charset?B?text?=`.
private func decodeRFC2047(_ input: String) -> String {
    let pattern = #"=\?([^?]+)\?([BbQq])\?([^?]*)\?="#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }

    let ns = input as NSString
    let matches = regex.matches(in: input, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return input }

    var result = ""
    var lastEnd = 0
    for match in matches {
        let fullRange = match.range
        let gap = ns.substring(with: NSRange(location: lastEnd, length: fullRange.location - lastEnd))
        // RFC 2047 §6.2: linear whitespace between adjacent encoded-words is discarded.
        if !(lastEnd > 0 && gap.allSatisfy(\.isWhitespace)) {
            result += gap
        }

        let charset = ns.substring(with: match.range(at: 1))
        let encoding = ns.substring(with: match.range(at: 2)).uppercased()
        let text = ns.substring(with: match.range(at: 3))

        if encoding == "Q" {
            let qText = text.replacingOccurrences(of: "_", with: " ")
            result += decodeRFC2047Bytes(decodeQuotedPrintableBytes(qText), charset: charset)
        } else {
            result += decodeRFC2047Bytes(Data(base64Encoded: text) ?? Data(), charset: charset)
        }
        lastEnd = fullRange.location + fullRange.length
    }
    result += ns.substring(from: lastEnd)
    return result.trimmingCharacters(in: .whitespaces)
}

private func decodeQuotedPrintableBytes(_ input: String) -> Data {
    var output = Data()
    let bytes = Array(input.utf8)
    var i = 0
    while i < bytes.count {
        let b = bytes[i]
        if b == UInt8(ascii: "=") {
            // Soft line break: =\r\n or =\n
            if i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "\r"),
               i + 2 < bytes.count, bytes[i + 2] == UInt8(ascii: "\n")
            {
                i += 3
                continue
            }
            if i + 1 < bytes.count, bytes[i + 1] == UInt8(ascii: "\n") {
                i += 2
                continue
            }
            if i + 2 < bytes.count,
               let hi = hexNibble(bytes[i + 1]),
               let lo = hexNibble(bytes[i + 2])
            {
                output.append(UInt8(hi * 16 + lo))
                i += 3
                continue
            }
        }
        output.append(b)
        i += 1
    }
    return output
}

private func hexNibble(_ byte: UInt8) -> Int? {
    switch byte {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): return Int(byte - UInt8(ascii: "0"))
    case UInt8(ascii: "A")...UInt8(ascii: "F"): return Int(byte - UInt8(ascii: "A") + 10)
    case UInt8(ascii: "a")...UInt8(ascii: "f"): return Int(byte - UInt8(ascii: "a") + 10)
    default: return nil
    }
}

private func decodeRFC2047Bytes(_ data: Data, charset: String) -> String {
    let encoding: String.Encoding
    switch charset.lowercased() {
    case "utf-8", "utf8": encoding = .utf8
    case "iso-8859-1", "latin1": encoding = .isoLatin1
    case "us-ascii", "ascii": encoding = .ascii
    default: encoding = .utf8
    }
    return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
}
