import Foundation
import CryptoKit

public enum SecretConstantsStoreError: Error, Equatable, Sendable {
    case sealFailed
    case openFailed
    case decodeFailed
    case encodeFailed
    case ioFailed
}

public struct SecretConstantsDocument: Equatable, Codable, Sendable {
    public var version: Int
    public var constants: [SecretConstant]

    public init(version: Int = 1, constants: [SecretConstant] = []) {
        self.version = version
        self.constants = constants
    }
}

/// Sealed App Support catalog (`secret-constants.sealed`) wrapped by one Keychain AES key.
public final class SecretConstantsStore: @unchecked Sendable {
    public static let fileName = "secret-constants.sealed"
    private static let magic = Data("MGSC".utf8)

    private let fileURL: URL
    private let keyProvider: any SecretConstantsKeyProviding
    private let lock = NSLock()
    private var catalog: SecretConstantsCatalog

    public init(fileURL: URL, keyProvider: any SecretConstantsKeyProviding) throws {
        self.fileURL = fileURL
        self.keyProvider = keyProvider
        self.catalog = try Self.loadCatalog(from: fileURL, keyProvider: keyProvider)
    }

    public convenience init(
        directory: URL,
        keyProvider: any SecretConstantsKeyProviding
    ) throws {
        try self.init(
            fileURL: directory.appendingPathComponent(Self.fileName),
            keyProvider: keyProvider
        )
    }

    public func snapshot() -> SecretConstantsCatalog {
        lock.lock()
        defer { lock.unlock() }
        return catalog
    }

    public func replace(_ next: SecretConstantsCatalog) throws {
        lock.lock()
        defer { lock.unlock() }
        try Self.save(catalog: next, to: fileURL, keyProvider: keyProvider)
        catalog = next
    }

    public func upsert(_ constant: SecretConstant) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = catalog
        try next.upsert(constant)
        try Self.save(catalog: next, to: fileURL, keyProvider: keyProvider)
        catalog = next
    }

    public func delete(name: String) throws {
        lock.lock()
        defer { lock.unlock() }
        var next = catalog
        next.delete(name: name)
        try Self.save(catalog: next, to: fileURL, keyProvider: keyProvider)
        catalog = next
    }

    // MARK: - Seal / open

    public static func seal(document: SecretConstantsDocument, key: SymmetricKey) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        guard let plaintext = try? encoder.encode(document) else {
            throw SecretConstantsStoreError.encodeFailed
        }
        guard let box = try? AES.GCM.seal(plaintext, using: key),
              let combined = box.combined
        else {
            throw SecretConstantsStoreError.sealFailed
        }
        return magic + combined
    }

    public static func open(blob: Data, key: SymmetricKey) throws -> SecretConstantsDocument {
        guard blob.count > magic.count, blob.prefix(magic.count) == magic else {
            throw SecretConstantsStoreError.openFailed
        }
        let combined = blob.dropFirst(magic.count)
        guard let box = try? AES.GCM.SealedBox(combined: combined),
              let plaintext = try? AES.GCM.open(box, using: key)
        else {
            throw SecretConstantsStoreError.openFailed
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let document = try? decoder.decode(SecretConstantsDocument.self, from: plaintext) else {
            throw SecretConstantsStoreError.decodeFailed
        }
        return document
    }

    private static func loadCatalog(
        from fileURL: URL,
        keyProvider: any SecretConstantsKeyProviding
    ) throws -> SecretConstantsCatalog {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            return SecretConstantsCatalog()
        }
        guard let blob = try? Data(contentsOf: fileURL) else {
            throw SecretConstantsStoreError.ioFailed
        }
        let key = try keyProvider.wrappingKey()
        let document = try open(blob: blob, key: key)
        return SecretConstantsCatalog(constants: document.constants)
    }

    private static func save(
        catalog: SecretConstantsCatalog,
        to fileURL: URL,
        keyProvider: any SecretConstantsKeyProviding
    ) throws {
        let key = try keyProvider.wrappingKey()
        let document = SecretConstantsDocument(constants: catalog.constants)
        let blob = try seal(document: document, key: key)
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try blob.write(to: fileURL, options: [.atomic])
        } catch {
            throw SecretConstantsStoreError.ioFailed
        }
    }
}
