import Foundation

public struct DraftVersion: Equatable, Sendable, Identifiable {
    public let id: String
    public let draftID: String
    public let label: String
    public let body: String
    public let savedAt: Date

    public init(
        id: String = UUID().uuidString,
        draftID: String,
        label: String,
        body: String,
        savedAt: Date = Date()
    ) {
        self.id = id
        self.draftID = draftID
        self.label = label
        self.body = body
        self.savedAt = savedAt
    }
}

public enum DraftLedgerError: Error, Equatable, Sendable {
    case notFound
}

/// In-memory versioned outbound drafts. No Mail-store writes.
public final class DraftLedger: @unchecked Sendable {
    private var versionsByDraft: [String: [DraftVersion]] = [:]
    private let lock = NSLock()

    public init() {}

    public func create(body: String) -> DraftVersion {
        let draftID = UUID().uuidString
        let version = DraftVersion(draftID: draftID, label: "v1", body: body)
        lock.lock()
        versionsByDraft[draftID] = [version]
        lock.unlock()
        return version
    }

    /// Appends a new version (newest-first in `list`).
    public func update(draftID: String, body: String) throws -> DraftVersion {
        lock.lock()
        defer { lock.unlock() }
        guard var versions = versionsByDraft[draftID] else {
            throw DraftLedgerError.notFound
        }
        let version = DraftVersion(
            draftID: draftID,
            label: "v\(versions.count + 1)",
            body: body
        )
        versions.insert(version, at: 0)
        versionsByDraft[draftID] = versions
        return version
    }

    public func list(draftID: String) throws -> [DraftVersion] {
        lock.lock()
        defer { lock.unlock() }
        guard let versions = versionsByDraft[draftID] else {
            throw DraftLedgerError.notFound
        }
        return versions
    }

    /// Returns body for clipboard / agent paste. No pasteboard side effects here.
    public func copy(versionID: String) throws -> String {
        lock.lock()
        defer { lock.unlock() }
        for versions in versionsByDraft.values {
            if let match = versions.first(where: { $0.id == versionID }) {
                return match.body
            }
        }
        throw DraftLedgerError.notFound
    }
}
