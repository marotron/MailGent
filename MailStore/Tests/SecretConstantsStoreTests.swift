import CryptoKit
import Foundation
import MailStore
import Testing

struct SecretConstantsStoreTests {
    private func tempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-secret-constants-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func constant(
        name: String = "phone_mobile",
        value: String = "+1-555-0100",
        agents: [String] = ["cursor"]
    ) -> SecretConstant {
        SecretConstant(
            name: name,
            label: "Mobile",
            hint: .phone,
            value: value,
            allowedAgentIDs: agents,
            multiline: false,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test func missingFileStartsEmpty() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = try InMemorySecretConstantsKeyProvider(rawKey: Data(repeating: 7, count: 32))
        let store = try SecretConstantsStore(directory: dir, keyProvider: key)
        #expect(store.snapshot().constants.isEmpty)
    }

    @Test func upsertPersistsAcrossReload() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = try InMemorySecretConstantsKeyProvider(rawKey: Data(repeating: 3, count: 32))

        let store = try SecretConstantsStore(directory: dir, keyProvider: key)
        try store.upsert(constant())
        #expect(store.snapshot().constants.count == 1)

        let reloaded = try SecretConstantsStore(directory: dir, keyProvider: key)
        #expect(reloaded.snapshot()["phone_mobile"]?.value == "+1-555-0100")
        #expect(reloaded.snapshot()["phone_mobile"]?.allowedAgentIDs == ["cursor"])
        #expect(reloaded.snapshot()["phone_mobile"]?.hint == .phone)
    }

    @Test func deletePersists() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = try InMemorySecretConstantsKeyProvider(rawKey: Data(repeating: 9, count: 32))
        let store = try SecretConstantsStore(directory: dir, keyProvider: key)
        try store.upsert(constant())
        try store.delete(name: "phone_mobile")

        let reloaded = try SecretConstantsStore(directory: dir, keyProvider: key)
        #expect(reloaded.snapshot().constants.isEmpty)
    }

    @Test func wrongKeyFailsClosed() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let keyA = try InMemorySecretConstantsKeyProvider(rawKey: Data(repeating: 1, count: 32))
        let keyB = try InMemorySecretConstantsKeyProvider(rawKey: Data(repeating: 2, count: 32))
        let store = try SecretConstantsStore(directory: dir, keyProvider: keyA)
        try store.upsert(constant())

        #expect(throws: SecretConstantsStoreError.openFailed) {
            _ = try SecretConstantsStore(directory: dir, keyProvider: keyB)
        }
    }

    @Test func sealRoundTripDocument() throws {
        let key = SymmetricKey(size: .bits256)
        let document = SecretConstantsDocument(constants: [constant(name: "home_address", value: "1 Main\nSt")])
        let blob = try SecretConstantsStore.seal(document: document, key: key)
        #expect(blob.starts(with: Data("MGSC".utf8)))
        let opened = try SecretConstantsStore.open(blob: blob, key: key)
        #expect(opened.constants[0].value == "1 Main\nSt")
    }
}
