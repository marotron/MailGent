import Foundation

public enum SecretConstantsCatalogError: Error, Equatable, Sendable {
    case invalidName(String)
    case notAllowlisted(names: [String], agentID: String)
}

public struct SecretConstantsCatalog: Equatable, Sendable {
    public private(set) var constants: [SecretConstant]

    public init(constants: [SecretConstant] = []) {
        self.constants = constants
    }

    public subscript(name: String) -> SecretConstant? {
        constants.first { $0.name == name }
    }

    public var dictionary: [String: SecretConstant] {
        Dictionary(uniqueKeysWithValues: constants.map { ($0.name, $0) })
    }

    /// Trim + validate lowercase snake_case. Returns nil when invalid.
    public static func normalizeName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SecretConstantPlaceholders.isValidName(trimmed) else { return nil }
        return trimmed
    }

    public mutating func upsert(_ constant: SecretConstant) throws {
        guard let name = Self.normalizeName(constant.name) else {
            throw SecretConstantsCatalogError.invalidName(constant.name)
        }
        var next = constant
        next.name = name
        if let index = constants.firstIndex(where: { $0.name == name }) {
            constants[index] = next
        } else {
            constants.append(next)
        }
    }

    public mutating func delete(name: String) {
        constants.removeAll { $0.name == name }
    }

    public func allowed(forAgentID agentID: String) -> [SecretConstant] {
        constants.filter { $0.allowedAgentIDs.contains(agentID) }
    }

    public func isAllowlisted(name: String, agentID: String) -> Bool {
        guard let constant = self[name] else { return false }
        return constant.allowedAgentIDs.contains(agentID)
    }

    /// Reject draft / propose_send insert when any token name is missing or not allowlisted for the agent.
    public func validateInsert(names: [String], agentID: String) throws {
        let unique = Array(Set(names)).sorted()
        let rejected = unique.filter { !isAllowlisted(name: $0, agentID: agentID) }
        if !rejected.isEmpty {
            throw SecretConstantsCatalogError.notAllowlisted(names: rejected, agentID: agentID)
        }
    }
}
