import Foundation
import MailStore
import Testing

struct LoopbackMCPServerTests {
    @Test func unauthenticatedCallIsRejected() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
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

    @Test func authenticatedSearchReturnsHits() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
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

    @Test func searchWithFTSOperatorSyntaxReturnsHitsNotInternalError() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "search", arguments: ["query": "from:amazon OR invoice"])
            )
        )

        #expect(response.status == 200)
        #expect(!response.body.contains(#""error":"internal""#))
        #expect(response.body.contains("items"))
        #expect(!response.body.contains("Invoice due"))
    }

    @Test func unknownToolReturnsIsErrorResultNotHTTP500() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "nope", arguments: [:])
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(!response.body.contains(#""error":"internal""#))
    }

    @Test func statusReturnsLastIngestAndNewestMessageDate() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "status", arguments: [:])
            )
        )

        #expect(response.status == 200)
        let payload = try Self.toolPayload(response.body)
        #expect(payload["newestMessageDate"] as? String == "Mon, 1 Jan 2024 00:00:00 +0000")
        #expect((payload["indexedCount"] as? NSNumber)?.intValue == 1)
        #expect(payload["lastIngestAt"] is String)
    }

    @Test func updateIngestsNewMailAndReturnsFreshness() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try env.root.writeEmlx(
            named: "2.emlx",
            rfc822: """
            From: Carol <carol@example.com>
            To: Bob <bob@example.com>
            Subject: Arrival
            Date: Tue, 2 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            New mail
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "update", arguments: [:])
            )
        )

        #expect(response.status == 200)
        let payload = try Self.toolPayload(response.body)
        #expect((payload["newCount"] as? NSNumber)?.intValue == 1)
        #expect(payload["newestMessageDate"] as? String == "Tue, 2 Jan 2024 00:00:00 +0000")
        #expect((payload["indexedCount"] as? NSNumber)?.intValue == 2)
        #expect(payload["lastIngestAt"] is String)
        #expect(env.audit.entries().contains { $0.kind == .updateIndex })
    }

    @Test func authenticatedGetReturnsMessage() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
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
        #expect(response.body.contains("finance@example.com"))
        #expect(try Self.extractJSONString(response.body, key: "bodyAccess") == "granted")
        #expect(env.audit.entries().contains { $0.kind == .get })
    }

    @Test func getWithBodyDeniedReportsNotGranted() async throws {
        let env = try LoopbackFixture(bodyGranted: false)
        defer { env.remove() }

        let response = await env.server.handle(
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
        #expect(try Self.extractJSONString(response.body, key: "bodyAccess") == "not_granted")
        #expect(try Self.extractJSONString(response.body, key: "note").contains("does not allow body access"))
        #expect(!response.body.contains("Please pay"))
        #expect(try Self.toolPayload(response.body)["body"] == nil)
    }

    @Test func initializeReturnsServerCapabilities() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
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

    @Test func toolsListReturnsReadTools() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
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
        #expect(response.body.contains("\"name\":\"create_draft\""))
        #expect(response.body.contains("\"name\":\"update_draft\""))
        #expect(response.body.contains("\"name\":\"set_source\""))
    }

    @Test func setSourceDeniedWhenSettingOff() async throws {
        let controller = FakeMailSourceController(agentMayChangeSource: false)
        let env = try LoopbackFixture(sourceController: controller)
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "set_source", arguments: ["source": "liveMail"])
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("MailGent Settings"))
        #expect(controller.source == .fixture)
        #expect(env.audit.entries().contains { $0.kind == .setSource && $0.outcome != .ok })
    }

    @Test func setSourceSwitchesWhenSettingOn() async throws {
        let controller = FakeMailSourceController(agentMayChangeSource: true)
        let env = try LoopbackFixture(sourceController: controller)
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "set_source", arguments: ["source": "liveMail"])
            )
        )

        #expect(response.status == 200)
        #expect(!response.body.contains("isError"))
        let payload = try Self.toolPayload(response.body)
        #expect(payload["source"] as? String == "liveMail")
        #expect((payload["agentMayChangeSource"] as? NSNumber)?.boolValue == true)
        #expect(controller.source == .liveMail)
        #expect(env.audit.entries().contains { $0.kind == .setSource && $0.outcome == .ok })
    }

    @Test func statusIncludesSourceWhenControllerBound() async throws {
        let controller = FakeMailSourceController(agentMayChangeSource: false)
        let env = try LoopbackFixture(sourceController: controller)
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "status", arguments: [:])
            )
        )

        #expect(response.status == 200)
        let payload = try Self.toolPayload(response.body)
        #expect(payload["source"] as? String == "fixture")
        #expect((payload["agentMayChangeSource"] as? NSNumber)?.boolValue == false)
        let status = try #require(env.audit.entries().last { $0.kind == .status })
        let logged = jsonObject(status.responseSummary)
        #expect(logged["source"] as? String == "fixture")
        #expect(logged["lastIngestAt"] is String)
        #expect(intValue(logged["indexedCount"]) == 1)
        #expect(status.requestSummary == "{}")
    }

    @Test func authenticatedCreateAndUpdateDraft() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let create = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "create_draft",
                    arguments: ["body": "Hello Ava"]
                )
            )
        )
        #expect(create.status == 200)
        #expect(create.body.contains("Hello Ava"))
        #expect(create.body.contains("draftID"))
        #expect(create.body.contains("v1"))
        #expect(env.audit.entries().contains { $0.kind == .createDraft })

        let draftID = try Self.extractJSONString(create.body, key: "draftID")
        let update = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "update_draft",
                    arguments: ["draftID": draftID, "body": "Hello Ava — revised"]
                )
            )
        )
        #expect(update.status == 200)
        #expect(update.body.contains("Hello Ava — revised"))
        #expect(update.body.contains("v2"))
        #expect(env.audit.entries().contains { $0.kind == .updateDraft })

        let versions = try env.server.ledger.list(draftID: draftID)
        #expect(versions.map(\.label) == ["v2", "v1"])
        #expect(try env.server.ledger.copy(versionID: versions[0].id) == "Hello Ava — revised")
    }

    @Test func initializedNotificationReturnsAccepted() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
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

    @Test func concurrentStatusCallsWithMainActorSourceDoNotHang() async throws {
        let controller = BlockingMailSourceController(
            snapshot: {
                await MainActor.run {
                    MailSourceSnapshot(source: .fixture, agentMayChangeSource: false)
                }
            },
            setSource: { source in
                await MainActor.run {
                    MailSourceSnapshot(source: source, agentMayChangeSource: true)
                }
            }
        )
        let env = try LoopbackFixture(sourceController: controller)
        defer { env.remove() }
        let box = ServerBox(env.server)
        let credential = env.credential

        await withTaskGroup(of: Int.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    let response = await box.server.handle(
                        LoopbackMCPRequest(
                            method: "POST",
                            path: "/mcp",
                            headers: ["Authorization": "Bearer \(credential)"],
                            body: Self.toolCallJSON(name: "status", arguments: [:])
                        )
                    )
                    return response.status
                }
            }
            var statuses: [Int] = []
            for await status in group {
                statuses.append(status)
            }
            #expect(statuses.allSatisfy { $0 == 200 })
            #expect(statuses.count == 8)
        }
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

    /// Pull a string value from the nested MCP tool JSON text payload.
    private static func extractJSONString(_ responseBody: String, key: String) throws -> String {
        let obj = try toolPayload(responseBody)
        guard let value = obj[key] as? String else {
            throw DraftLedgerError.notFound
        }
        return value
    }

    private static func toolPayload(_ responseBody: String) throws -> [String: Any] {
        struct RPC: Decodable {
            struct Result: Decodable {
                struct Content: Decodable {
                    let text: String
                }
                let content: [Content]
            }
            let result: Result
        }
        let rpc = try JSONDecoder().decode(RPC.self, from: Data(responseBody.utf8))
        guard let text = rpc.result.content.first?.text,
              let data = text.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw DraftLedgerError.notFound
        }
        return obj
    }
}

private func jsonObject(_ text: String) -> [String: Any] {
    guard let data = text.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return [:] }
    return obj
}

private func intValue(_ any: Any?) -> Int? {
    switch any {
    case let n as Int: n
    case let n as NSNumber: n.intValue
    default: nil
    }
}

private struct LoopbackFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let audit: AuditLog
    let server: LoopbackMCPServer

    init(bodyGranted: Bool = true, sourceController: (any MailSourceControlling)? = nil) throws {
        root = try FixtureTree()
        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Cc: Finance <finance@example.com>
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
        try grants.allow(
            agentID: agent.id,
            accountID: accountID,
            fields: GrantFields(envelope: true, body: bodyGranted)
        )
        let gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            audit: audit
        )
        server = LoopbackMCPServer(gateway: gateway, sourceController: sourceController)
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}

private final class ServerBox: @unchecked Sendable {
    let server: LoopbackMCPServer
    init(_ server: LoopbackMCPServer) { self.server = server }
}

private final class FakeMailSourceController: MailSourceControlling, @unchecked Sendable {
    var source: MailSourceID
    var agentMayChangeSource: Bool

    init(source: MailSourceID = .fixture, agentMayChangeSource: Bool) {
        self.source = source
        self.agentMayChangeSource = agentMayChangeSource
    }

    func snapshot() async -> MailSourceSnapshot {
        MailSourceSnapshot(source: source, agentMayChangeSource: agentMayChangeSource)
    }

    func setSource(_ source: MailSourceID) async throws -> MailSourceSnapshot {
        guard agentMayChangeSource else { throw MailSourceError.denied }
        self.source = source
        return await snapshot()
    }
}
