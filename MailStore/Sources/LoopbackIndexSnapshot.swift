import Foundation

/// Companion index lifecycle exposed to the loopback MCP (status + 503 bodies).
public struct LoopbackIndexSnapshot: Equatable, Sendable {
    public enum Phase: String, Sendable, Equatable {
        case notStarted
        case indexing
        case ready
        case failed
    }

    public let phase: Phase
    public let indexedSoFar: Int
    public let totalHint: Int?
    public let currentTask: String?
    public let statusMessage: String?

    public init(
        phase: Phase,
        indexedSoFar: Int = 0,
        totalHint: Int? = nil,
        currentTask: String? = nil,
        statusMessage: String? = nil
    ) {
        self.phase = phase
        self.indexedSoFar = indexedSoFar
        self.totalHint = totalHint
        self.currentTask = currentTask
        self.statusMessage = statusMessage
    }

    public static let notStarted = LoopbackIndexSnapshot(
        phase: .notStarted,
        statusMessage: "Index not started"
    )

    public var isReady: Bool { phase == .ready }

    public func asJSON(freshness: IndexFreshness? = nil, extra: [String: Any] = [:]) -> [String: Any] {
        AuditJSON.indexStatus(self, freshness: freshness, extra: extra)
    }
}

extension AuditJSON {
    static func indexStatus(
        _ snapshot: LoopbackIndexSnapshot,
        freshness: IndexFreshness? = nil,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "state": snapshot.phase.rawValue,
            "indexedSoFar": snapshot.indexedSoFar
        ]
        if let totalHint = snapshot.totalHint {
            payload["totalHint"] = totalHint
        }
        if let currentTask = snapshot.currentTask, !currentTask.isEmpty {
            payload["currentTask"] = currentTask
        }
        if let statusMessage = snapshot.statusMessage, !statusMessage.isEmpty {
            payload["message"] = statusMessage
        }
        if let freshness {
            payload.merge(AuditJSON.freshness(freshness)) { _, new in new }
            payload["state"] = snapshot.phase.rawValue
        } else {
            payload["indexedCount"] = snapshot.indexedSoFar
        }
        for (key, value) in extra {
            payload[key] = value
        }
        return payload
    }
}
