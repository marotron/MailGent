import Foundation
import MailStore
import Testing

struct AgentReadAPITests {
    @Test func searchWithoutCredentialIsRejected() throws {
        let env = try AgentReadFixture()
        defer { env.remove() }

        #expect(throws: PairingError.unauthorized) {
            try env.gateway.search("invoice", credential: nil)
        }
    }

    @Test func searchWithWrongCredentialIsRejected() throws {
        let env = try AgentReadFixture()
        defer { env.remove() }

        #expect(throws: PairingError.unauthorized) {
            try env.gateway.search("invoice", credential: "wrong")
        }
    }

    @Test func authenticatedSearchReturnsGrantedMail() throws {
        let env = try AgentReadFixture()
        defer { env.remove() }

        let page = try env.gateway.search("invoice", credential: env.credential)
        #expect(page.items.map(\.subject) == ["Invoice due"])
    }

    @Test func getRedactsSecretsWhenLeakGuardEnabled() throws {
        let env = try LeakGuardReadFixture(body: "password=hunter2\nPlease pay")
        defer { env.remove() }

        let message = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .text("[REDACTED:passwordCtx]\nPlease pay"))
        #expect(message.leakGuardAccess?.bodyAccess == .sanitized)
        #expect(message.leakGuardAccess?.sanitizedRules.contains("Password patterns") == true)
    }

    @Test func searchSanitizesSubjectWhenLeakGuardEnabled() throws {
        let env = try LeakGuardReadFixture(
            subject: "token=abc123 invoice",
            body: "Please pay"
        )
        defer { env.remove() }

        let page = try env.gateway.search("invoice", credential: env.credential)
        #expect(page.items.first?.subject == "[REDACTED:passwordCtx] invoice")
    }
}

private struct AgentReadFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
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
            .appendingPathComponent("MailGent-agent-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        let pairing = Pairing()
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
            grants: grants
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}

private struct LeakGuardReadFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let accountID: String
    let gateway: AgentReadAPI

    init(subject: String = "Invoice due", body: String = "Please pay") throws {
        root = try FixtureTree()
        accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: \(subject)
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            \(body)
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-leak-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        let pairing = Pairing()
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        let grants = GrantGate()
        try grants.allow(agentID: agent.id, accountID: accountID, placement: "INBOX")
        let policy = OutboundLeakGuardPolicy(
            enabled: true,
            scopes: [OutboundLeakGuardPolicy.scopeKey(accountID: accountID, placement: "INBOX")],
            builtInClasses: [.passwordCtx: true]
        )
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            leakGuard: OutboundLeakGuard(policy: policy)
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}
