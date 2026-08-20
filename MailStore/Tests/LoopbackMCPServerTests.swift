import Foundation
import MailStore
import Testing

struct LoopbackMCPServerTests {
    @Test func unauthenticatedCallIsRejected() throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: [:],
                body: Self.toolCallJSON(name: "search", arguments: ["query": "invoice"])
            )
        )

        #expect(response.status == 401)
        #expect(response.body.contains("unauthorized"))
    }

    @Test func authenticatedSearchReturnsHits() throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "search", arguments: ["query": "invoice"])
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("Invoice due"))
        #expect(response.body.contains("accountID"))
        #expect(response.body.contains("placement"))
        #expect(response.body.contains("items"))
        #expect(env.audit.entries().contains { $0.kind == .search && $0.detail == "invoice" })
    }

    @Test func authenticatedGetReturnsMessage() throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "get",
                    arguments: [
                        "accountID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        "placement": "INBOX",
                        "id": "1"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("Invoice due"))
        #expect(response.body.contains("Please pay"))
        #expect(response.body.contains("alice@example.com"))
        #expect(env.audit.entries().contains { $0.kind == .get })
    }

    @Test func initializeReturnsServerCapabilities() throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cursor","version":"1"}}}"#.utf8)
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("\"protocolVersion\":\"2025-03-26\""))
        #expect(response.body.contains("\"name\":\"mailgent\""))
        #expect(response.body.contains("\"tools\""))
    }

    @Test func toolsListReturnsReadTools() throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8)
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("\"name\":\"search\""))
        #expect(response.body.contains("\"name\":\"list\""))
        #expect(response.body.contains("\"name\":\"get\""))
        #expect(response.body.contains("\"name\":\"listPlacements\""))
    }

    @Test func initializedNotificationReturnsAccepted() throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)
            )
        )

        #expect(response.status == 202)
        #expect(response.body.isEmpty)
    }

    private static func toolCallJSON(name: String, arguments: [String: String]) -> Data {
        let args = arguments
            .map { "\"\($0.key)\":\"\($0.value)\"" }
            .joined(separator: ",")
        let json = """
        {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\(name)","arguments":{\(args)}}}
        """
        return Data(json.utf8)
    }
}

private struct LoopbackFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let audit: AuditLog
    let server: LoopbackMCPServer

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
            .appendingPathComponent("MailGent-mcp-\(UUID().uuidString).sqlite")
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
        let gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            audit: audit
        )
        server = LoopbackMCPServer(gateway: gateway)
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}
