import Foundation
import SQLite3

/// PROTOTYPE-validated — resolves Apple Mail account UUID → human label + email.
public enum MailAccountIdentitySource: String, Equatable, Sendable {
    case accountsDatabase
    case inferredHeaders
    case fallback
}

public struct MailAccountIdentity: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let email: String?
    public let source: MailAccountIdentitySource

    public init(id: String, displayName: String, email: String?, source: MailAccountIdentitySource) {
        self.id = id
        self.displayName = displayName
        self.email = email
        self.source = source
    }
}

public enum MailAccountIdentityResolver {
    /// Resolves identities for every account folder under `store`.
    public static func resolve(in store: MailStore, accountsDatabases: [URL]? = nil) throws -> [MailAccountIdentity] {
        let nameMap = loadNameMap(accountsDatabases: accountsDatabases)
        let versionRoot = try MailStore.resolveVersionRoot(in: store.root)

        return try store.accounts().map { account in
            let folder = versionRoot.appendingPathComponent(account.id, isDirectory: true)
            if let info = nameMap[account.id.lowercased()] {
                return MailAccountIdentity(
                    id: account.id,
                    displayName: info.displayName,
                    email: info.username,
                    source: .accountsDatabase
                )
            }
            if let inferred = inferIdentity(from: folder) {
                return MailAccountIdentity(
                    id: account.id,
                    displayName: inferred.displayName,
                    email: inferred.username,
                    source: .inferredHeaders
                )
            }
            return MailAccountIdentity(
                id: account.id,
                displayName: fallbackDisplayName(for: account.id),
                email: nil,
                source: .fallback
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public static func lookup(_ identities: [MailAccountIdentity]) -> [String: MailAccountIdentity] {
        Dictionary(uniqueKeysWithValues: identities.map { ($0.id, $0) })
    }

    public static var defaultMailLibraryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mail", isDirectory: true)
    }

    public static var defaultAccountsDatabaseURLs: [URL] {
        let accounts = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Accounts", isDirectory: true)
        return ["Accounts4.sqlite", "Accounts3.sqlite"].map {
            accounts.appendingPathComponent($0)
        }
    }

    // MARK: - Private

    private struct AccountInfo {
        let displayName: String
        let username: String?
    }

    private static func loadNameMap(accountsDatabases: [URL]?) -> [String: AccountInfo] {
        let candidates = accountsDatabases ?? defaultAccountsDatabaseURLs
        for url in candidates {
            if let map = readAccountsDatabase(at: url), !map.isEmpty {
                return map
            }
        }
        return [:]
    }

    private static func readAccountsDatabase(at url: URL) -> [String: AccountInfo]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db
        else { return nil }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT ZIDENTIFIER, ZACCOUNTDESCRIPTION, ZUSERNAME
        FROM ZACCOUNT
        WHERE ZIDENTIFIER IS NOT NULL;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK,
              let statement
        else { return nil }
        defer { sqlite3_finalize(statement) }

        var map: [String: AccountInfo] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let idPtr = sqlite3_column_text(statement, 0) else { continue }
            let id = String(cString: idPtr)
            let description: String? = {
                guard let ptr = sqlite3_column_text(statement, 1) else { return nil }
                let value = String(cString: ptr).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }()
            let username: String? = {
                guard let ptr = sqlite3_column_text(statement, 2) else { return nil }
                let value = String(cString: ptr).trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }()

            let displayName = description
                ?? username.flatMap(displayName(fromEmail:))
                ?? fallbackDisplayName(for: id)
            map[id.lowercased()] = AccountInfo(displayName: displayName, username: username)
        }
        return map
    }

    private static func inferIdentity(from accountURL: URL) -> AccountInfo? {
        let samples = sampleEmlxURLs(in: accountURL)
        var counts: [String: Int] = [:]

        for file in samples {
            guard let headers = try? headerBlock(fromEmlx: file) else { continue }
            for address in candidateAddresses(in: headers, preferSent: isUnderSentMailbox(file)) {
                counts[address, default: 0] += 1
            }
        }

        guard let best = counts.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        })?.key else { return nil }

        return AccountInfo(
            displayName: best,
            username: best
        )
    }

    private static func sampleEmlxURLs(in accountURL: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: accountURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sent: [URL] = []
        var inbox: [URL] = []
        var other: [URL] = []

        for case let item as URL in enumerator {
            let name = item.lastPathComponent.lowercased()
            guard name.hasSuffix(".emlx"), !name.hasSuffix(".emlxpart") else { continue }
            if isUnderSentMailbox(item) {
                sent.append(item)
            } else if isUnderInboxMailbox(item) {
                inbox.append(item)
            } else {
                other.append(item)
            }
            if sent.count >= 8 && inbox.count >= 8 { break }
        }

        return Array(sent.prefix(8)) + Array(inbox.prefix(8)) + Array(other.prefix(4))
    }

    private static func isUnderSentMailbox(_ url: URL) -> Bool {
        url.pathComponents.contains { component in
            let lower = component.lowercased()
            return lower.contains("sent") && lower.hasSuffix(".mbox")
        }
    }

    private static func isUnderInboxMailbox(_ url: URL) -> Bool {
        url.pathComponents.contains { component in
            let lower = component.lowercased()
            return (lower == "inbox.mbox" || lower.hasPrefix("inbox")) && lower.hasSuffix(".mbox")
        }
    }

    private static func headerBlock(fromEmlx url: URL) throws -> String {
        let parsed = try MailStore.parseEmlx(url)
        let text = String(decoding: parsed.data.prefix(8_192), as: UTF8.self)
        let (headerBlock, _) = MailStore.splitHeadersAndBody(text)
        return headerBlock
    }

    private static func candidateAddresses(in headers: String, preferSent: Bool) -> [String] {
        var results: [String] = []
        let lines = unfoldedHeaderLines(headers)

        func values(named names: [String]) -> [String] {
            names.flatMap { name in
                lines.compactMap { line -> String? in
                    guard line.lowercased().hasPrefix(name.lowercased() + ":") else { return nil }
                    return String(line.dropFirst(name.count + 1))
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }

        let fields: [String]
        if preferSent {
            fields = values(named: ["From"])
        } else {
            fields = values(named: ["Delivered-To", "X-Original-To", "X-Delivered-To", "To"])
                + values(named: ["From"])
        }

        for field in fields {
            for address in extractEmails(from: field) where !results.contains(address) {
                results.append(address)
            }
        }
        return results
    }

    private static func unfoldedHeaderLines(_ headers: String) -> [String] {
        var lines: [String] = []
        for raw in headers.components(separatedBy: CharacterSet.newlines) {
            if raw.first?.isWhitespace == true, let last = lines.popLast() {
                lines.append(last + " " + raw.trimmingCharacters(in: .whitespaces))
            } else if !raw.isEmpty {
                lines.append(raw)
            }
        }
        return lines
    }

    private static func extractEmails(from field: String) -> [String] {
        let pattern = #"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(field.startIndex..<field.endIndex, in: field)
        return regex.matches(in: field, range: range).compactMap { match in
            guard let r = Range(match.range, in: field) else { return nil }
            return String(field[r]).lowercased()
        }
    }

    /// `billing@acme.co.uk` → `Acme`; known providers keep friendly labels.
    public static func displayName(fromEmail email: String) -> String? {
        let parts = email.split(separator: "@")
        guard parts.count == 2 else { return nil }
        let domain = String(parts[1]).lowercased()

        let known: [String: String] = [
            "icloud.com": "iCloud",
            "me.com": "iCloud",
            "mac.com": "iCloud",
            "gmail.com": "Gmail",
            "googlemail.com": "Gmail",
            "outlook.com": "Outlook",
            "hotmail.com": "Hotmail",
            "live.com": "Outlook",
            "yahoo.com": "Yahoo",
            "aol.com": "AOL",
        ]
        if let label = known[domain] { return label }

        let labels = domain.split(separator: ".")
        guard let brand = labels.first, brand.count >= 2 else { return nil }
        let skip = Set(["mail", "smtp", "imap", "email", "mx", "www"])
        let chosen: Substring
        if skip.contains(String(brand)), labels.count >= 2 {
            chosen = labels[1]
        } else {
            chosen = brand
        }
        return chosen.prefix(1).uppercased() + chosen.dropFirst().lowercased()
    }

    private static func fallbackDisplayName(for id: String) -> String {
        let short = id.split(separator: "-").first.map(String.init) ?? String(id.prefix(8))
        return "Account \(short)"
    }
}
