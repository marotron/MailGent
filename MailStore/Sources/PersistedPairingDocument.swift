import Foundation

/// One agent row in `pairing.json` (v2).
public struct PersistedAgentCredential: Codable, Equatable, Sendable {
    public var agentID: String
    public var name: String
    public var trustClass: String
    public var credential: String

    public init(agentID: String, name: String, trustClass: String, credential: String) {
        self.agentID = agentID
        self.name = name
        self.trustClass = trustClass
        self.credential = credential
    }
}

/// On-disk pairing document. v1 was a single agent at the root; v2 is an agents array.
public struct PersistedPairingDocument: Codable, Equatable, Sendable {
    public var version: Int
    public var agents: [PersistedAgentCredential]
    public var selectedAgentID: String?

    public init(
        version: Int = 2,
        agents: [PersistedAgentCredential],
        selectedAgentID: String? = nil
    ) {
        self.version = version
        self.agents = agents
        self.selectedAgentID = selectedAgentID
    }

    /// Decode v2, or wrap a legacy v1 single-agent file. `migrated` is true when the caller should rewrite v2.
    public static func decodeMigrating(from data: Data) throws -> (document: PersistedPairingDocument, migrated: Bool) {
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           root["agents"] is [Any]
        {
            let document = try JSONDecoder().decode(PersistedPairingDocument.self, from: data)
            return (document, false)
        }

        struct V1: Codable {
            let agentID: String
            let name: String
            let trustClass: String
            let credential: String
        }

        let v1 = try JSONDecoder().decode(V1.self, from: data)
        let agent = PersistedAgentCredential(
            agentID: v1.agentID,
            name: v1.name,
            trustClass: v1.trustClass,
            credential: v1.credential
        )
        let document = PersistedPairingDocument(
            version: 2,
            agents: [agent],
            selectedAgentID: v1.agentID
        )
        return (document, true)
    }
}
