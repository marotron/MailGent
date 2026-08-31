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

    @Test func getWithholdsBodyWhenBlockWhole() throws {
        let env = try LeakGuardReadFixture(
            body: "password=hunter2\nPlease pay",
            bodyHitMode: .blockWhole
        )
        defer { env.remove() }

        let message = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .text(""))
        #expect(message.leakGuardAccess?.bodyAccess == .withheldConfidential)
        #expect(message.leakGuardAccess?.bodyAccessReason == .leakGuard)
        #expect(message.leakGuardAccess?.sanitizedRules.contains("Password patterns") == true)
    }

    @Test func getStealthReplaceReportsGrantedBodyAccess() throws {
        let rule = CustomLeakRule(
            label: "My name",
            kind: .literal,
            pattern: "Marotron",
            action: .replace,
            actionValue: "John Smith",
            discloseToAgent: false
        )
        let env = try LeakGuardReadFixture(
            body: "From Marotron",
            builtIns: [:],
            customRules: [rule]
        )
        defer { env.remove() }

        let message = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .text("From John Smith"))
        #expect(message.leakGuardAccess?.bodyAccess == .granted)
        #expect(message.leakGuardAccess?.bodyAccessReason == .grant)
        #expect(message.leakGuardAccess?.sanitizedRules.isEmpty == true)
        #expect(message.leakGuardAccess?.stealth == true)
    }

    @Test func getAuditRefRetainsOriginalsWhenSanitized() throws {
        let env = try LeakGuardReadFixture(
            body: "password=hunter2\nPlease pay",
            audit: true
        )
        defer { env.remove() }

        _ = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        let get = try #require(env.audit?.entries().last { $0.kind == .get })
        let response = leakGuardJSON(get.responseSummary)
        #expect(response["bodyAccess"] as? String == "sanitized")
        #expect(response["bodyAccessReason"] as? String == "leak_guard")
        #expect((response["sanitizedRules"] as? [String])?.contains("Password patterns") == true)
        #expect(get.messages.count == 1)
        #expect(get.messages[0].bodyOriginal == "password=hunter2\nPlease pay")
        #expect(get.messages[0].sanitizedRules?.contains("Password patterns") == true)
        #expect(get.messages[0].bodyAccess == .sanitized)
        #expect(get.messages[0].leakDetectionCount >= 1)
        #expect(
            get.messages[0].leakDetections?.contains {
                $0.field == .body && $0.label == "Password patterns" && $0.disposition == .redacted
            } == true
        )
    }

    @Test func getDoesNotScanDeniedBodyEvenWithLeakGuard() throws {
        let env = try LeakGuardReadFixture(
            body: "password=hunter2\nPlease pay",
            bodyGranted: false
        )
        defer { env.remove() }

        let message = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .notGranted)
        #expect(message.leakGuardAccess?.bodyAccess == .notGranted)
        #expect(message.leakGuardAccess?.bodyAccessReason == .grant)
        #expect(message.leakGuardAccess?.sanitizedRules.isEmpty == true)
    }

    @Test func unprotectedScopeSkipsLeakGuardOnGet() throws {
        let env = try LeakGuardReadFixture(
            body: "password=hunter2\nPlease pay",
            scopes: ["work/Sent"]
        )
        defer { env.remove() }

        let message = try env.gateway.get(
            credential: env.credential,
            accountID: env.accountID,
            placement: "INBOX",
            id: "1"
        )
        #expect(message.body == .text("password=hunter2\nPlease pay"))
        #expect(message.leakGuardAccess?.bodyAccess == .granted)
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
    let audit: AuditLog?
    let gateway: AgentReadAPI

    init(
        subject: String = "Invoice due",
        body: String = "Please pay",
        bodyGranted: Bool = true,
        bodyHitMode: LeakGuardHitMode = .redactSpans,
        subjectHitMode: LeakGuardHitMode = .redactSpans,
        builtIns: [BuiltInLeakClass: Bool]? = [.passwordCtx: true],
        customRules: [CustomLeakRule] = [],
        scopes: Set<String>? = nil,
        audit: Bool = false
    ) throws {
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

        let auditLog = audit ? AuditLog() : nil
        self.audit = auditLog
        let pairing = Pairing(audit: auditLog)
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        let grants = GrantGate()
        try grants.allow(
            agentID: agent.id,
            accountID: accountID,
            placement: "INBOX",
            fields: GrantFields(envelope: true, body: bodyGranted)
        )
        let scopeSet = scopes ?? [
            OutboundLeakGuardPolicy.scopeKey(accountID: accountID, placement: "INBOX")
        ]
        let policy = OutboundLeakGuardPolicy(
            enabled: true,
            scopes: scopeSet,
            builtInClasses: builtIns,
            customRules: customRules,
            subjectHitMode: subjectHitMode,
            bodyHitMode: bodyHitMode
        )
        gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            leakGuard: OutboundLeakGuard(policy: policy),
            audit: auditLog
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}

private func leakGuardJSON(_ text: String) -> [String: Any] {
    guard let data = text.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return obj
}
