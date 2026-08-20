import Foundation
import MailStore
import Testing

struct LoopbackHTTPListenerTests {
    @Test func bindsLoopbackAndRejectsMissingBearer() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let listener = LoopbackHTTPListener(gateway: env.gateway, host: "127.0.0.1", port: 0)
        try await listener.start()
        defer { listener.stop() }

        let port = try #require(listener.boundPort)
        let url = URL(string: "http://127.0.0.1:\(port)/mcp")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"t","version":"1"}}}"#.utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        #expect(http.statusCode == 401)
    }

    @Test func authenticatedInitializeOverHTTPSucceeds() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let listener = LoopbackHTTPListener(gateway: env.gateway, host: "127.0.0.1", port: 0)
        try await listener.start()
        defer { listener.stop() }

        let port = try #require(listener.boundPort)
        let url = URL(string: "http://127.0.0.1:\(port)/mcp")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(env.credential)", forHTTPHeaderField: "Authorization")
        request.httpBody = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cursor","version":"1"}}}"#.utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try #require(response as? HTTPURLResponse)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(http.statusCode == 200)
        #expect(body.contains("mailgent"))
    }
}

private struct LoopbackFixture {
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
            .appendingPathComponent("MailGent-http-\(UUID().uuidString).sqlite")
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
