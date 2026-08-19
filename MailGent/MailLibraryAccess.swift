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
