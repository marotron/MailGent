import Foundation

/// Security-scoped bookmark for the Personal vault root (experimental propose-send context).
enum PersonalVaultBookmark {
    static let defaultsKey = MailGentPreferences.personalVaultRootBookmarkKey

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

    static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultsKey)
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

    static func displayPath(defaults: UserDefaults = .standard) -> String? {
        resolvedURL(defaults: defaults)?.path
    }
}
