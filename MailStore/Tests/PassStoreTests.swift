import Foundation
import MailStore
import Testing

struct PassStoreTests {
    @Test func snapshotRoundTripsDefinitionsAndEnablements() throws {
        let pass = Pass(
            id: "p1",
            name: "Invoices",
            nick: "A",
            fromRules: [MatchRule(value: "billing@", mode: .contains)],
            subjectRules: [MatchRule(value: "invoice", mode: .starts)],
            betweenJoin: .and,
            fields: GrantFields(envelope: false, body: true, attachmentMetadata: true),
            agentIDs: ["agent-1", "agent-2"]
        )
        let enablements = [
            PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX"),
            PassEnablement(passID: "p1", accountID: "acc-1", placement: nil)
        ]
        let original = PassSnapshot(passes: [pass], enablements: enablements)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PassSnapshot.self, from: data)

        #expect(decoded == original)
        #expect(decoded.passes[0].nick == "A")
        #expect(decoded.passes[0].betweenJoin == .and)
        #expect(decoded.passes[0].fields.body == true)
        #expect(decoded.enablements.count == 2)
    }

    @Test func storeReplaceRestoresSnapshot() {
        let store = PassStore()
        let pass = Pass(
            id: "p1",
            name: "Invoices",
            nick: "A",
            subjectRules: [MatchRule(value: "invoice", mode: .contains)],
            fields: GrantFields(envelope: false, body: true),
            agentIDs: ["agent-1"]
        )
        store.replace(
            with: PassSnapshot(
                passes: [pass],
                enablements: [PassEnablement(passID: "p1", accountID: "acc-1", placement: "INBOX")]
            )
        )

        #expect(store.allPasses() == [pass])
        #expect(store.isEnabled(passID: "p1", accountID: "acc-1", placement: "INBOX"))
        #expect(!store.isEnabled(passID: "p1", accountID: "acc-1", placement: "Sent"))
    }
}
