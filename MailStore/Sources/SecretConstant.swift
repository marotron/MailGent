import Foundation

public enum SecretConstantHint: String, Codable, Sendable, CaseIterable {
    case phone
    case address
    case id
    case other
}

public struct SecretConstant: Equatable, Codable, Sendable, Identifiable {
    public var name: String
    public var label: String
    public var hint: SecretConstantHint?
    public var value: String
    public var allowedAgentIDs: [String]
    public var multiline: Bool
    public var updatedAt: Date

    public var id: String { name }

    public init(
        name: String,
        label: String,
        hint: SecretConstantHint? = nil,
        value: String,
        allowedAgentIDs: [String] = [],
        multiline: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.name = name
        self.label = label
        self.hint = hint
        self.value = value
        self.allowedAgentIDs = allowedAgentIDs
        self.multiline = multiline
        self.updatedAt = updatedAt
    }
}
