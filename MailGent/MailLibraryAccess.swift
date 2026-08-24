import Foundation

enum MailLibraryAccess: Equatable, Sendable {
    case granted
    case denied
}

struct MailLibraryAccessSnapshot: Equatable, Sendable {
    var canListMailDirectory: Bool
    var hasReadableFolderBookmark: Bool

    var access: MailLibraryAccess {
        if canListMailDirectory || hasReadableFolderBookmark {
            .granted
        } else {
            .denied
        }
    }

    /// Human status: can we list Mail, not whether the FDA toggle is on.
    var headline: String {
        access == .granted ? "Mail folder readable" : "Grant access to Mail"
    }

    var explanation: String {
        switch access {
        case .granted:
            if hasReadableFolderBookmark, !canListMailDirectory {
                return "Indexing uses the Mail folder you chose. Full Disk Access in System Settings is not required for messages. Enable it if account names stay as UUIDs — those labels come from ~/Library/Accounts, which is outside Mail."
            }
            return "This process can list ~/Library/Mail, which is enough to index messages. The Full Disk Access switch in System Settings can stay off. Enable it if account names stay as UUIDs — those labels come from ~/Library/Accounts, which is outside Mail."
        case .denied:
            return "MailGent only needs to read ~/Library/Mail. macOS has no Files & Folders toggle for Mail. Use Full Disk Access, or Choose Mail Folder… for that directory only. Then Recheck."
        }
    }
}

enum MailLibraryProbe {
    static var defaultMailDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(component: "Library")
            .appending(component: "Mail")
    }

    static func canList(_ url: URL) -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )
            return true
        } catch {
            return false
        }
    }

    static func resolvedMailRoot() -> URL? {
        if canList(defaultMailDirectory) {
            return defaultMailDirectory
        }
        if let bookmark = MailFolderBookmark.resolvedURL(), canList(bookmark) {
            return bookmark
        }
        return nil
    }
}

enum MailFolderBookmark {
    static let defaultsKey = "mailFolderBookmark"

    static func save(_ url: URL, defaults: UserDefaults = .standard) throws {
        let data: Data
        do {
            data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            data = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        }
        defaults.set(data, forKey: defaultsKey)
    }

    static func resolvedURL(defaults: UserDefaults = .standard) -> URL? {
        guard let data = defaults.data(forKey: defaultsKey) else { return nil }
        var stale = false
        let scoped = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        let url = scoped ?? (try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ))
        guard let url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}
