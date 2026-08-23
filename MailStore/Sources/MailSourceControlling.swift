import Foundation

/// On-disk / companion mail source the agent can observe (and switch, if allowed).
public enum MailSourceID: String, CaseIterable, Sendable, Equatable {
    case fixture
    case liveMail
}

public struct MailSourceSnapshot: Equatable, Sendable {
    public let source: MailSourceID
    public let agentMayChangeSource: Bool

    public init(source: MailSourceID, agentMayChangeSource: Bool) {
        self.source = source
        self.agentMayChangeSource = agentMayChangeSource
    }
}

public enum MailSourceError: Error, Equatable, CustomStringConvertible {
    case denied
    case unavailable
    case unknownSource
    case notAvailable

    public var description: String {
        switch self {
        case .denied:
            return "Mail source change is disabled. Enable it in MailGent Settings → General."
        case .unavailable:
            return "That mail source is not available. Grant Full Disk Access in MailGent Settings → Access, or pick another source."
        case .unknownSource:
            return "Unknown source. Use fixture or liveMail."
        case .notAvailable:
            return "Mail source control is not bound."
        }
    }
}

public protocol MailSourceControlling: Sendable {
    func snapshot() async -> MailSourceSnapshot
    func setSource(_ source: MailSourceID) async throws -> MailSourceSnapshot
}

extension MailSourceID {
    /// Ordered sources the UI/agent may land on. Append future sources here.
    public static func available(liveMailAccessible: Bool) -> [MailSourceID] {
        if liveMailAccessible {
            return [.fixture, .liveMail]
        }
        return [.fixture]
    }

    /// Next entry in `sources`, wrapping. If `self` is missing, first available.
    public func next(in sources: [MailSourceID]) -> MailSourceID {
        guard !sources.isEmpty else { return self }
        guard let index = sources.firstIndex(of: self) else { return sources[0] }
        return sources[(index + 1) % sources.count]
    }
}

/// Forwards companion source changes into MCP `status` / `set_source`.
public final class BlockingMailSourceController: MailSourceControlling, @unchecked Sendable {
    public typealias SnapshotWork = @Sendable () async -> MailSourceSnapshot
    public typealias SetWork = @Sendable (MailSourceID) async throws -> MailSourceSnapshot

    private let snapshotWork: SnapshotWork
    private let setWork: SetWork

    public init(snapshot: @escaping SnapshotWork, setSource: @escaping SetWork) {
        self.snapshotWork = snapshot
        self.setWork = setSource
    }

    public func snapshot() async -> MailSourceSnapshot {
        await snapshotWork()
    }

    public func setSource(_ source: MailSourceID) async throws -> MailSourceSnapshot {
        try await setWork(source)
    }
}
