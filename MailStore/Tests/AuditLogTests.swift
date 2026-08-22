import Foundation
import MailStore
import Testing

struct AuditLogTests {
    @Test func searchAppendsAuditEntryInspectableByAPI() throws {
        let env = try AuditFixture()
        defer { env.remove() }

        _ = try env.gateway.search("invoice", credential: env.credential)

        let searches = env.audit.entries().filter { $0.kind == .search }
        #expect(searches.count == 1)
        #expect(searches[0].agentName == "Cursor")
        #expect(searches[0].detail == "invoice")
        #expect(searches[0].requestSummary.contains("q=invoice"))
        #expect(searches[0].responseSummary == "1 messages")
        #expect(searches[0].messages.count == 1)
        #expect(searches[0].messages[0].subject == "Invoice due")
        #expect(searches[0].messages[0].to.contains("bob@example.com"))
        #expect(searches[0].messages[0].fields.body == true)
        #expect(searches[0].outcome == .ok)
        #expect(searches[0].finishedAt != nil)
    }

    @Test func getAppendsAuditEntry() throws {
        let env = try AuditFixture()
        defer { env.remove() }

        let hit = try env.gateway.search("invoice", credential: env.credential).items[0]
        _ = try env.gateway.get(
            credential: env.credential,
            accountID: hit.accountID,
            placement: hit.placement,
            id: hit.id
        )

        let kinds = env.audit.entries().map(\.kind)
        #expect(kinds == [.pair, .search, .get])
        let get = env.audit.entries().last!
        #expect(get.responseSummary == "bodyAccess=granted")
        #expect(get.messages.count == 1)
        #expect(get.messages[0].id == hit.id)
    }

    @Test func listAndStatusAreAudited() throws {
        let env = try AuditFixture()
        defer { env.remove() }

        _ = try env.gateway.list(credential: env.credential)
        _ = try env.gateway.listPlacements(credential: env.credential)
        _ = try env.gateway.freshness(credential: env.credential)

        let kinds = env.audit.entries().map(\.kind)
        #expect(kinds.contains(.list))
        #expect(kinds.contains(.listPlacements))
        #expect(kinds.contains(.status))
        let list = env.audit.entries().first { $0.kind == .list }!
        #expect(list.responseSummary == "1 messages")
        let placements = env.audit.entries().first { $0.kind == .listPlacements }!
        #expect(placements.placements.count == 1)
    }

    @Test func persistsAcrossReload() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-audit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let audit = AuditLog(fileURL: url)
        audit.append(
            AuditEntry(
                id: "keep-me",
                kind: .search,
                agentID: "a",
                agentName: "Cursor",
                detail: "invoice",
                requestSummary: "q=invoice limit=25",
                responseSummary: "1 messages"
            )
        )
        #expect(audit.byteCount() > 0)

        let reloaded = AuditLog(fileURL: url)
        #expect(reloaded.entries().count == 1)
        #expect(reloaded.entries()[0].id == "keep-me")
        #expect(reloaded.entries()[0].detail == "invoice")
    }

    @Test func retentionCapsCountAgeAndBytes() {
        let now = Date()
        let audit = AuditLog(
            policy: AuditRetention(maxAge: 3_600, maxCount: 2, maxBytes: nil)
        )
        audit.append(
            AuditEntry(
                kind: .status,
                agentID: "a",
                agentName: "Cursor",
                detail: "old",
                at: now.addingTimeInterval(-7_200)
            )
        )
        audit.append(
            AuditEntry(kind: .status, agentID: "a", agentName: "Cursor", detail: "a", at: now)
        )
        audit.append(
            AuditEntry(kind: .status, agentID: "a", agentName: "Cursor", detail: "b", at: now)
        )
        audit.append(
            AuditEntry(kind: .status, agentID: "a", agentName: "Cursor", detail: "c", at: now)
        )
        #expect(audit.entries().map(\.detail) == ["b", "c"])

        let bulky = AuditLog(policy: AuditRetention(maxBytes: 400))
        for i in 0..<20 {
            bulky.append(
                AuditEntry(
                    kind: .status,
                    agentID: "a",
                    agentName: "Cursor",
                    detail: String(repeating: "x", count: 80) + "\(i)"
                )
            )
        }
        #expect(bulky.entries().count < 20)
        #expect(bulky.byteCount() <= 400 || bulky.entries().count == 1)
    }

    @Test func removeAllAndOlderThan() {
        let now = Date()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-audit-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let audit = AuditLog(fileURL: url)
        audit.append(
            AuditEntry(
                kind: .status,
                agentID: "a",
                agentName: "Cursor",
                detail: "old",
                at: now.addingTimeInterval(-86_400 * 2)
            )
        )
        audit.append(
            AuditEntry(kind: .status, agentID: "a", agentName: "Cursor", detail: "new", at: now)
        )
        audit.removeOlderThan(now.addingTimeInterval(-86_400))
        #expect(audit.entries().map(\.detail) == ["new"])
        #expect(FileManager.default.fileExists(atPath: url.path))

        audit.removeAll()
        #expect(audit.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(audit.byteCount() == 0)
    }

    @Test func pairAndRevokeAreAudited() throws {
        let audit = AuditLog()
        let pairing = Pairing(audit: audit)
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: "secret"
        )
        pairing.revoke(agentID: agent.id)

        #expect(audit.entries().map(\.kind) == [.pair, .revoke])
        #expect(audit.entries().map(\.agentName) == ["Cursor", "Cursor"])
    }
}

private struct AuditFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let audit: AuditLog
    let gateway: AgentReadAPI

    init() throws {
        root = try FixtureTree()
        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Invoice due
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            Please pay
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-audit-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        audit = AuditLog()
        let pairing = Pairing(audit: audit)
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        let grants = GrantGate()
        try grants.allow(agentID: agent.id, accountID: accountID)
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            audit: audit
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}
