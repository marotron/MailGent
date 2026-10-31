import Foundation
import CryptoKit
import Security

public protocol SecretConstantsKeyProviding: Sendable {
    func wrappingKey() throws -> SymmetricKey
}

public enum SecretConstantsKeyError: Error, Equatable, Sendable {
    case keychainFailed(OSStatus)
    case invalidKeyLength
}

/// Deterministic in-memory key for tests.
public struct InMemorySecretConstantsKeyProvider: SecretConstantsKeyProviding {
    private let key: SymmetricKey

    public init(key: SymmetricKey = SymmetricKey(size: .bits256)) {
        self.key = key
    }

    public init(rawKey: Data) throws {
        guard rawKey.count == 32 else { throw SecretConstantsKeyError.invalidKeyLength }
        self.key = SymmetricKey(data: rawKey)
    }

    public func wrappingKey() throws -> SymmetricKey {
        key
    }
}

/// One AES-256 wrapping key in the login Keychain (`secret-constants.wrapping-key`).
public struct KeychainSecretConstantsKeyProvider: SecretConstantsKeyProviding {
    public static let account = "secret-constants.wrapping-key"
    public static let service = "app.mailgent.MailGent"

    public init() {}

    public func wrappingKey() throws -> SymmetricKey {
        if let existing = try load() {
            return existing
        }
        let key = SymmetricKey(size: .bits256)
        try save(key)
        return key
    }

    private func load() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SecretConstantsKeyError.keychainFailed(status)
        }
        guard data.count == 32 else {
            throw SecretConstantsKeyError.invalidKeyLength
        }
        return SymmetricKey(data: data)
    }

    private func save(_ key: SymmetricKey) throws {
        let data = key.withUnsafeBytes { Data($0) }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: Self.account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(
                [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: Self.service,
                    kSecAttrAccount as String: Self.account,
                ] as CFDictionary,
                update as CFDictionary
            )
            guard updateStatus == errSecSuccess else {
                throw SecretConstantsKeyError.keychainFailed(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else {
            throw SecretConstantsKeyError.keychainFailed(status)
        }
    }
}
