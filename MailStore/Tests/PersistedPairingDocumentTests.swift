import Foundation
import MailStore
import Testing

struct PersistedPairingDocumentTests {
    @Test func v1SingleAgentMigratesToV2() throws {
        let v1 = """
        {
          "agentID": "agent-cursor",
          "name": "Cursor",
          "trustClass": "machine-local",
          "credential": "secret-token"
        }
        """.data(using: .utf8)!

        let (document, migrated) = try PersistedPairingDocument.decodeMigrating(from: v1)
        #expect(migrated)
        #expect(document.version == 2)
        #expect(document.agents.count == 1)
        #expect(document.agents[0].agentID == "agent-cursor")
        #expect(document.agents[0].name == "Cursor")
        #expect(document.selectedAgentID == "agent-cursor")
    }

    @Test func v2RoundTripsWithoutMigrationFlag() throws {
        let original = PersistedPairingDocument(
            version: 2,
            agents: [
                PersistedAgentCredential(
                    agentID: "a1",
                    name: "Cursor",
                    trustClass: "machine-local",
                    credential: "tok-a"
                ),
                PersistedAgentCredential(
                    agentID: "a2",
                    name: "Grok Bot",
                    trustClass: "machine-local",
                    credential: "tok-b"
                ),
            ],
            selectedAgentID: "a2"
        )
        let data = try JSONEncoder().encode(original)
        let (document, migrated) = try PersistedPairingDocument.decodeMigrating(from: data)
        #expect(!migrated)
        #expect(document == original)
    }
}
