import CryptoKit
import Foundation

public struct PairedAgent: Equatable, Sendable {
    public let id: String
    public let name: String
    public let trustClass: AgentTrustClass

    public init(id: String, name: String, trustClass: AgentTrustClass) {
        self.id = id
        self.name = name
        self.trustClass = trustClass
    }
}

public enum AgentTrustClass: String, Equatable, Sendable {
    case machineLocal = "machine-local"
}

public enum PairingError: Error, Equatable, Sendable {
    case unauthorized
}

public final class Pairing: @unchecked Sendable {
    private struct Record {
        let agent: PairedAgent
        let credentialHash: Data
    }

    private var records: [Record] = []
    private let lock = NSLock()
    private let audit: AuditLog?

    public init(audit: AuditLog? = nil) {
        self.audit = audit
    }

    @discardableResult
    public func register(
        name: String,
        trustClass: AgentTrustClass,
        credential: String
    ) throws -> PairedAgent {
        let agent = PairedAgent(
            id: UUID().uuidString,
            name: name,
            trustClass: trustClass
        )
        let record = Record(agent: agent, credentialHash: Self.hash(credential))
        lock.lock()
        records.append(record)
        lock.unlock()
        audit?.append(
            AuditEntry(kind: .pair, agentID: agent.id, agentName: agent.name)
        )
        return agent
    }

    public func authenticate(credential: String?) throws -> PairedAgent {
        guard let credential, !credential.isEmpty else {
            throw PairingError.unauthorized
        }
        let candidate = Self.hash(credential)
        lock.lock()
        defer { lock.unlock() }
        guard let match = records.first(where: { record in
            timingSafeEqual(record.credentialHash, candidate)
        }) else {
            throw PairingError.unauthorized
        }
        return match.agent
    }

    public func revoke(agentID: String) {
        lock.lock()
        let name = records.first { $0.agent.id == agentID }?.agent.name ?? ""
        records.removeAll { $0.agent.id == agentID }
        lock.unlock()
        guard !name.isEmpty else { return }
        audit?.append(
            AuditEntry(kind: .revoke, agentID: agentID, agentName: name)
        )
    }

    /// Rehydrate a previously paired agent without emitting a new pair audit event.
    public func restore(agent: PairedAgent, credential: String) {
        let record = Record(agent: agent, credentialHash: Self.hash(credential))
        lock.lock()
        records.removeAll { $0.agent.id == agent.id }
        records.append(record)
        lock.unlock()
    }

    private static func hash(_ credential: String) -> Data {
        Data(SHA256.hash(data: Data(credential.utf8)))
    }

    private func timingSafeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<lhs.count {
            diff |= lhs[i] ^ rhs[i]
        }
        return diff == 0
    }
}
