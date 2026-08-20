import Foundation
import MailStore
import Testing

struct DraftLedgerTests {
    @Test func createStartsDraftWithVersionOne() {
        let ledger = DraftLedger()
        let version = ledger.create(body: "Hello Ava")

        #expect(version.label == "v1")
        #expect(version.body == "Hello Ava")
        #expect(!version.id.isEmpty)
        #expect(!version.draftID.isEmpty)

        let listed = try! ledger.list(draftID: version.draftID)
        #expect(listed.count == 1)
        #expect(listed[0].id == version.id)
    }

    @Test func updateAppendsNextVersion() throws {
        let ledger = DraftLedger()
        let first = ledger.create(body: "v1 body")
        let second = try ledger.update(draftID: first.draftID, body: "v2 body")

        #expect(second.label == "v2")
        #expect(second.body == "v2 body")
        #expect(second.draftID == first.draftID)
        #expect(second.id != first.id)

        let listed = try ledger.list(draftID: first.draftID)
        #expect(listed.map(\.label) == ["v2", "v1"])
    }

    @Test func updateUnknownDraftFailsClosed() {
        let ledger = DraftLedger()
        #expect(throws: DraftLedgerError.notFound) {
            try ledger.update(draftID: "missing", body: "nope")
        }
    }

    @Test func copyReturnsVersionBody() throws {
        let ledger = DraftLedger()
        let first = ledger.create(body: "copy me")
        let body = try ledger.copy(versionID: first.id)
        #expect(body == "copy me")
    }

    @Test func copyUnknownVersionFailsClosed() {
        let ledger = DraftLedger()
        #expect(throws: DraftLedgerError.notFound) {
            try ledger.copy(versionID: "missing")
        }
    }

    @Test func listUnknownDraftFailsClosed() {
        let ledger = DraftLedger()
        #expect(throws: DraftLedgerError.notFound) {
            try ledger.list(draftID: "missing")
        }
    }
}
