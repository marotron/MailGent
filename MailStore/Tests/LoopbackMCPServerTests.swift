import Foundation
import MailStore
import SQLite3
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
        #expect(payload["state"] as? String == "ready")
    }

    @Test func indexingSearchReturns503WithProgress() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let host = LoopbackHost(
            pairing: env.pairing,
            audit: env.audit,
            grants: env.grants
        )
        host.setIndexState(
            LoopbackIndexSnapshot(
                phase: .indexing,
                indexedSoFar: 12,
                totalHint: 40,
                currentTask: "Indexing INBOX",
                statusMessage: "Indexing INBOX"
            )
        )
        let server = LoopbackMCPServer(host: host)

        let response = await server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "search", arguments: ["query": "invoice"])
            )
        )

        #expect(response.status == 503)
        #expect(response.body.contains("Index not ready"))
        #expect(response.body.contains("indexing"))
        #expect(response.body.contains("12"))
        #expect(response.body.contains("40"))
    }

    @Test func indexingStatusReturnsProgressWithoutGateway() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let host = LoopbackHost(
            pairing: env.pairing,
            audit: env.audit,
            grants: env.grants
        )
        host.setIndexState(
            LoopbackIndexSnapshot(
                phase: .indexing,
                indexedSoFar: 12,
                totalHint: 40,
                currentTask: "Indexing INBOX",
                statusMessage: "Indexing INBOX"
            )
        )
        let server = LoopbackMCPServer(host: host)

        let response = await server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "status", arguments: [:])
            )
        )

        #expect(response.status == 200)
        let payload = try Self.toolPayload(response.body)
        #expect(payload["state"] as? String == "indexing")
        #expect((payload["indexedSoFar"] as? NSNumber)?.intValue == 12)
        #expect((payload["totalHint"] as? NSNumber)?.intValue == 40)
        #expect(payload["currentTask"] as? String == "Indexing INBOX")
    }

    @Test func initializeWorksWhileIndexing() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let host = LoopbackHost(
            pairing: env.pairing,
            audit: env.audit,
            grants: env.grants
        )
        host.setIndexState(
            LoopbackIndexSnapshot(phase: .indexing, indexedSoFar: 1, totalHint: 10)
        )
        let server = LoopbackMCPServer(host: host)

        let response = await server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(
                    #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"cursor","version":"1"}}}"#
                        .utf8
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("mailgent"))
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

    @Test func updateReportsRemovedCountWhenMessageLeavesDisk() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        try FileManager.default.removeItem(
            at: env.root.mailboxURL(
                account: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                mailbox: "INBOX.mbox"
            )
            .appendingPathComponent("Messages/1.emlx")
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
        #expect((payload["newCount"] as? NSNumber)?.intValue == 0)
        #expect((payload["removedCount"] as? NSNumber)?.intValue == 1)
        #expect((payload["indexedCount"] as? NSNumber)?.intValue == 0)
    }

    @Test func listNewReturnsMessagesFromLastUpdate() async throws {
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

        _ = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "update", arguments: [:])
            )
        )

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "list_new", arguments: [:])
            )
        )

        #expect(response.status == 200)
        let payload = try Self.toolPayload(response.body)
        #expect((payload["count"] as? NSNumber)?.intValue == 1)
        let items = payload["items"] as? [[String: Any]]
        #expect(items?.count == 1)
        #expect(items?.first?["subject"] as? String == "Arrival")
        #expect(items?.first?["id"] as? String == "2")
        #expect(payload["nextCursor"] == nil)
        #expect(env.audit.entries().contains { $0.kind == .listNew })
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
        let payload = try Self.toolPayload(response.body)
        #expect(payload["bodyAccess"] as? String == "not_granted")
        #expect(payload["bodyAccessReason"] as? String == "grant")
        #expect(payload["body"] == nil)
        #expect(!response.body.contains("Please pay"))
    }

    @Test func getReportsSanitizedLeakGuardFields() async throws {
        let env = try LoopbackFixture(
            body: "password=hunter2\nPlease pay",
            leakGuard: OutboundLeakGuard(
                policy: OutboundLeakGuardPolicy(
                    enabled: true,
                    scopes: ["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/INBOX"],
                    builtInClasses: [.passwordCtx: true]
                )
            )
        )
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
        let payload = try Self.toolPayload(response.body)
        #expect(payload["subjectAccess"] as? String == "granted")
        #expect(payload["bodyAccess"] as? String == "sanitized")
        #expect(payload["bodyAccessReason"] as? String == "leak_guard")
        #expect((payload["sanitizedRules"] as? [String])?.contains("Password patterns") == true)
        #expect(payload["body"] as? String == "password=[REDACTED:passwordCtx]\nPlease pay")
        #expect(payload["note"] == nil)
    }

    @Test func getReportsWithheldConfidentialWhenBlockWhole() async throws {
        let env = try LoopbackFixture(
            body: "password=hunter2\nPlease pay",
            leakGuard: OutboundLeakGuard(
                policy: OutboundLeakGuardPolicy(
                    enabled: true,
                    scopes: ["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/INBOX"],
                    builtInClasses: [.passwordCtx: true],
                    bodyHitMode: .blockWhole
                )
            )
        )
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
        let payload = try Self.toolPayload(response.body)
        #expect(payload["bodyAccess"] as? String == "withheld_confidential")
        #expect(payload["bodyAccessReason"] as? String == "leak_guard")
        #expect(payload["body"] == nil)
    }

    @Test func getStealthReplaceIncludesNoteNotSanitizedRules() async throws {
        let rule = CustomLeakRule(
            label: "My name",
            kind: .literal,
            pattern: "Marotron",
            action: .replace,
            actionValue: "John Smith",
            discloseToAgent: false
        )
        let env = try LoopbackFixture(
            body: "From Marotron",
            leakGuard: OutboundLeakGuard(
                policy: OutboundLeakGuardPolicy(
                    enabled: true,
                    scopes: ["AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/INBOX"],
                    builtInClasses: [:],
                    customRules: [rule]
                )
            )
        )
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
        let payload = try Self.toolPayload(response.body)
        #expect(payload["bodyAccess"] as? String == "granted")
        #expect(payload["bodyAccessReason"] as? String == "grant")
        #expect(payload["sanitizedRules"] == nil)
        #expect((payload["note"] as? String)?.contains("substituted on device") == true)
        #expect(payload["body"] as? String == "From John Smith")
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
        #expect(response.body.contains("\"name\":\"list_new\""))
        #expect(response.body.contains("\"name\":\"get\""))
        #expect(response.body.contains("\"name\":\"get_attachment\""))
        #expect(response.body.contains("\"name\":\"open_in_mail\""))
        #expect(response.body.contains("\"name\":\"propose_send\""))
        #expect(response.body.contains("\"name\":\"await_propose_send\""))
        #expect(response.body.contains("\"name\":\"list_accounts\""))
        #expect(!response.body.contains("\"name\":\"listNew\""))
        #expect(!response.body.contains("\"name\":\"list_placements\""))
        #expect(!response.body.contains("\"name\":\"listPlacements\""))
        #expect(!response.body.contains("\"name\":\"listAccounts\""))
        #expect(!response.body.contains("\"name\":\"openInMail\""))
        #expect(!response.body.contains("\"name\":\"proposeSend\""))
        #expect(!response.body.contains("\"name\":\"awaitProposeSend\""))
        #expect(response.body.contains("\"name\":\"create_draft\""))
        #expect(response.body.contains("\"name\":\"update_draft\""))
        #expect(response.body.contains("\"name\":\"set_source\""))
        // Always listed (even when master toggle off) so MCP clients need not reconnect.
        #expect(response.body.contains("\"name\":\"list_secrets\""))
    }

    @Test func listSecretsErrorsWhenDisabled() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "list_secrets", arguments: [:])
            )
        )
        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("Secret constants are disabled"))
        let entries = env.audit.entries().filter { $0.kind == .listSecrets }
        #expect(entries.count == 1)
        #expect(entries[0].outcome != .ok)
        #expect(!entries[0].responseSummary.contains("+1-555"))
    }

    @Test func listSecretsReturnsAllowlistedWhenEnabled() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }
        let agent = try env.server.host.authenticate(env.credential)
        var catalog = SecretConstantsCatalog()
        try catalog.upsert(
            SecretConstant(
                name: "phone_mobile",
                label: "Mobile",
                hint: .phone,
                value: "+1-555-0100",
                allowedAgentIDs: [agent.id]
            )
        )
        env.server.host.setSecretConstants(enabled: true, catalog: catalog)

        let list = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8)
            )
        )
        #expect(list.body.contains("\"name\":\"list_secrets\""))

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(name: "list_secrets", arguments: [:])
            )
        )
        #expect(response.status == 200)
        #expect(!response.body.contains("isError"))
        #expect(response.body.contains("phone_mobile"))
        #expect(response.body.contains("Mobile"))
        #expect(response.body.contains("phone"))
        #expect(!response.body.contains("+1-555-0100"))
        let entries = env.audit.entries().filter { $0.kind == .listSecrets }
        #expect(entries.count == 1)
        #expect(entries[0].outcome == .ok)
        #expect(entries[0].responseSummary.contains("phone_mobile"))
        #expect(!entries[0].responseSummary.contains("+1-555-0100"))
    }

    @Test func awaitProposeSendSoftWaitNotLoggedByDefault() async throws {
        // Soft timeout clamps to ≥1s; keep the human decision pending longer so we get awaiting_user.
        let env = try LoopbackFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return .cancel
            }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "a@b.c", "subject": "Hi", "body": "Hello"]
        )
        let proposalId = try #require(ack["proposalId"] as? String)
        let before = env.audit.entries().filter { $0.kind == .awaitProposeSend }.count

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: try Self.toolCallJSONObject(
                    name: "await_propose_send",
                    arguments: ["proposalId": proposalId, "timeout": 1]
                )
            )
        )
        let payload = try Self.toolPayload(response.body)
        #expect(payload["status"] as? String == "awaiting_user")
        #expect(env.audit.entries().filter { $0.kind == .awaitProposeSend }.count == before)
    }

    @Test func awaitProposeSendSoftWaitLoggedWhenEnabled() async throws {
        let env = try LoopbackFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                return .cancel
            }
        )
        defer { env.remove() }
        env.server.host.setLogAwaitProposeSendSoftWaits(true)

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "a@b.c", "subject": "Hi", "body": "Hello"]
        )
        let proposalId = try #require(ack["proposalId"] as? String)

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: try Self.toolCallJSONObject(
                    name: "await_propose_send",
                    arguments: ["proposalId": proposalId, "timeout": 1]
                )
            )
        )
        let payload = try Self.toolPayload(response.body)
        #expect(payload["status"] as? String == "awaiting_user")
        #expect(env.audit.entries().contains {
            $0.kind == .awaitProposeSend && $0.detail.hasPrefix("awaiting_user")
        })
    }

    @Test func createDraftRejectsTokensWhenSecretConstantsDisabled() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "create_draft",
                    arguments: ["body": "Call [[mg:phone_mobile]]"]
                )
            )
        )
        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("Secret constants are disabled"))
    }

    @Test func createDraftAcceptsAllowlistedTokenAndKeepsBodyTokenized() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }
        let agent = try env.server.host.authenticate(env.credential)
        var catalog = SecretConstantsCatalog()
        try catalog.upsert(
            SecretConstant(
                name: "phone_mobile",
                label: "Mobile",
                hint: .phone,
                value: "+1-555-0100",
                allowedAgentIDs: [agent.id]
            )
        )
        env.server.host.setSecretConstants(enabled: true, catalog: catalog)

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "create_draft",
                    arguments: ["body": "Call [[mg:phone_mobile]]"]
                )
            )
        )
        #expect(response.status == 200)
        #expect(!response.body.contains("isError"))
        #expect(response.body.contains("[[mg:phone_mobile]]"))
        #expect(!response.body.contains("+1-555-0100"))
    }

    @Test func createDraftRejectsNonAllowlistedToken() async throws {
        let env = try LoopbackFixture()
        defer { env.remove() }
        var catalog = SecretConstantsCatalog()
        try catalog.upsert(
            SecretConstant(
                name: "phone_mobile",
                label: "Mobile",
                hint: .phone,
                value: "+1-555-0100",
                allowedAgentIDs: ["other-agent"]
            )
        )
        env.server.host.setSecretConstants(enabled: true, catalog: catalog)

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "create_draft",
                    arguments: ["body": "Call [[mg:phone_mobile]]"]
                )
            )
        )
        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("not allowlisted"))
        #expect(response.body.contains("phone_mobile"))
    }

    @Test func openInMailOpensGrantedMessage() async throws {
        let opener = FakeAppleMailOpener(result: true)
        let env = try LoopbackFixture(
            appleMailOpener: opener,
            agentMayOpenInMail: true,
            internetMessageID: "<hello.42@example.com>"
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "open_in_mail",
                    arguments: [
                        "accountID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        "placement": "INBOX",
                        "id": "1"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(!response.body.contains("isError"))
        let payload = try Self.toolPayload(response.body)
        #expect((payload["opened"] as? NSNumber)?.boolValue == true)
        #expect(payload["internetMessageID"] as? String == "<hello.42@example.com>")
        #expect(payload["mailURL"] as? String == "message://%3Chello.42%40example.com%3E")
        #expect(opener.openedIDs == ["<hello.42@example.com>"])
        let opened = env.audit.entries().contains { entry in
            entry.kind == .openInMail && entry.outcome == .ok
        }
        #expect(opened)
    }

    @Test func openInMailDeniedWhenSettingOff() async throws {
        let opener = FakeAppleMailOpener(result: true)
        let env = try LoopbackFixture(
            appleMailOpener: opener,
            agentMayOpenInMail: false,
            internetMessageID: "<hello.42@example.com>"
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "open_in_mail",
                    arguments: [
                        "accountID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        "placement": "INBOX",
                        "id": "1"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("MailGent Settings"))
        #expect(opener.openedIDs.isEmpty)
        #expect(env.audit.entries().contains {
            $0.kind == .openInMail && $0.outcome != .ok
        })
    }

    @Test func openInMailFailsWhenMessageIDMissing() async throws {
        let opener = FakeAppleMailOpener(result: true)
        let env = try LoopbackFixture(appleMailOpener: opener, agentMayOpenInMail: true)
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "open_in_mail",
                    arguments: [
                        "accountID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        "placement": "INBOX",
                        "id": "1"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("Message-ID"))
        #expect(opener.openedIDs.isEmpty)
        #expect(env.audit.entries().contains {
            $0.kind == .openInMail && $0.outcome != .ok
        })
    }

    @Test func openInMailFailsWhenOpenerUnset() async throws {
        let env = try LoopbackFixture(
            agentMayOpenInMail: true,
            internetMessageID: "<hello.42@example.com>"
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "open_in_mail",
                    arguments: [
                        "accountID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        "placement": "INBOX",
                        "id": "1"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("opener"))
        #expect(env.audit.entries().contains {
            $0.kind == .openInMail && $0.outcome != .ok
        })
    }

    @Test func openInMailFailsWhenOpenerReturnsFalse() async throws {
        let opener = FakeAppleMailOpener(result: false)
        let env = try LoopbackFixture(
            appleMailOpener: opener,
            agentMayOpenInMail: true,
            internetMessageID: "<hello.42@example.com>"
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "open_in_mail",
                    arguments: [
                        "accountID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        "placement": "INBOX",
                        "id": "1"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("did not open"))
        #expect(opener.openedIDs == ["<hello.42@example.com>"])
        let failed = env.audit.entries().contains { entry in
            entry.kind == .openInMail && entry.outcome != .ok
        }
        #expect(failed)
    }

    @Test func proposeSendDeniedWhenSettingOff() async throws {
        let outgoing = FakeMailOutgoingSender()
        let env = try LoopbackFixture(
            mailOutgoingSender: outgoing,
            agentMayProposeSend: false,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "propose_send",
                    arguments: [
                        "to": "alex@example.com",
                        "subject": "Hi",
                        "body": "Hello"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("MailGent Settings"))
        #expect(outgoing.deliveries.isEmpty)
        #expect(env.audit.entries().contains {
            $0.kind == .proposeSend && $0.outcome != .ok
        })
    }

    @Test func proposeSendAcksAwaitingUser() async throws {
        let outgoing = FakeMailOutgoingSender()
        let env = try LoopbackFixture(
            mailOutgoingSender: outgoing,
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        let ack = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(
                    """
                    {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"propose_send","arguments":{"to":["Alex <alex@example.com>"],"subject":"Hi","body":"Hello","cc":"ops@example.com"}}}
                    """.utf8
                )
            )
        )

        #expect(ack.status == 200)
        #expect(!ack.body.contains("isError"))
        let payload = try Self.toolPayload(ack.body)
        #expect(payload["status"] as? String == "awaiting_user")
        #expect(payload["proposalId"] as? String != nil)
        #expect(payload["expiresAt"] as? String != nil)
        #expect(outgoing.deliveries.isEmpty)
        #expect(env.audit.entries().contains {
            $0.kind == .proposeSend && $0.detail.hasPrefix("awaiting_user")
        })
    }

    @Test func proposeSendHumanCancelAuditedWithoutAwait() async throws {
        let env = try LoopbackFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in .cancel }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "alex@example.com", "subject": "Hi", "body": "Hello"]
        )
        let proposalId = try #require(ack["proposalId"] as? String)

        // Human decision is audited at resolve — not only when an agent later awaits.
        var sawCancel = false
        for _ in 0..<40 {
            if env.audit.entries().contains(where: {
                $0.kind == .proposeSend && $0.detail.hasPrefix("cancelled")
            }) {
                sawCancel = true
                break
            }
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        #expect(sawCancel)
        #expect(env.audit.entries().contains {
            $0.kind == .proposeSend && $0.detail.hasPrefix("awaiting_user")
        })
        // No await yet → no await_propose_send receipt row.
        #expect(!env.audit.entries().contains { $0.kind == .awaitProposeSend })
        _ = proposalId
    }

    @Test func awaitProposeSendReturnsSendOutcome() async throws {
        let outgoing = FakeMailOutgoingSender()
        let env = try LoopbackFixture(
            mailOutgoingSender: outgoing,
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: [
                "to": ["Alex <alex@example.com>"],
                "subject": "Hi",
                "body": "Hello",
                "cc": "ops@example.com"
            ]
        )
        let proposalId = try #require(ack["proposalId"] as? String)
        let payload = try await Self.awaitProposeSendPayload(
            env.server,
            credential: env.credential,
            proposalId: proposalId
        )
        #expect(payload["outcome"] as? String == "send")
        #expect(outgoing.deliveries.count == 1)
        #expect(outgoing.deliveries[0].mode == .send)
        #expect(outgoing.deliveries[0].proposal.to == ["Alex <alex@example.com>"])
        #expect(outgoing.deliveries[0].proposal.cc == ["ops@example.com"])
        #expect(env.audit.entries().contains {
            $0.kind == .awaitProposeSend && $0.outcome == .ok && $0.detail.hasPrefix("send")
        })
    }

    @Test func proposeSendDedupesSameFingerprint() async throws {
        let env = try LoopbackFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return .cancel
            }
        )
        defer { env.remove() }

        let first = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "a@b.c", "subject": "Hi", "body": "Hello"]
        )
        let second = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "a@b.c", "subject": "Hi", "body": "Hello"]
        )
        #expect(first["proposalId"] as? String == second["proposalId"] as? String)
    }

    @Test func awaitProposeSendUnknownIdErrors() async throws {
        let env = try LoopbackFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in .cancel }
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "await_propose_send",
                    arguments: ["proposalId": "missing-id"]
                )
            )
        )
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("Unknown") || response.body.contains("proposalId"))
    }

    @Test func proposeSendIgnoresContextWhenExperimentalOff() async throws {
        let box = ProposalCaptureBox()
        let env = try LoopbackFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            agentMayProposeSend: true,
            proposeSendContextExperimental: false,
            sendProposalPrompter: { proposal in
                box.value = proposal
                return .cancel
            }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: [
                "to": ["a@b.c"],
                "subject": "Hi",
                "body": "Hello",
                "context": ["casePath": "../escape", "events": [] as [Any]]
            ]
        )
        let proposalId = try #require(ack["proposalId"] as? String)
        _ = try await Self.awaitProposeSendPayload(
            env.server,
            credential: env.credential,
            proposalId: proposalId
        )
        #expect(box.value?.context == nil)
    }

    @Test func proposeSendParsesContextWhenExperimentalOn() async throws {
        let box = ProposalCaptureBox()
        let env = try LoopbackFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            agentMayProposeSend: true,
            proposeSendContextExperimental: true,
            sendProposalPrompter: { proposal in
                box.value = proposal
                return .cancel
            }
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(
                    """
                    {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"propose_send","arguments":{"to":["a@b.c"],"subject":"Hi","body":"Hello","context":{"casePath":"cases/acme","caseLabel":"Acme","events":[{"id":"e1","kind":"note","scope":"private","ownership":"you","at":"2026-10-20T11:40:00Z","summary":"Prep","source":{"vault":{"path":"LOG.md"}}}]}}}}
                    """.utf8
                )
            )
        )

        #expect(response.status == 200)
        #expect(!response.body.contains("isError"))
        let ack = try Self.toolPayload(response.body)
        let proposalId = try #require(ack["proposalId"] as? String)
        _ = try await Self.awaitProposeSendPayload(
            env.server,
            credential: env.credential,
            proposalId: proposalId
        )
        #expect(box.value?.context?.casePath == "cases/acme")
        #expect(box.value?.context?.caseLabel == "Acme")
        #expect(box.value?.context?.events.count == 1)
    }

    @Test func proposeSendRejectsBadContextWhenExperimentalOn() async throws {
        let env = try LoopbackFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            agentMayProposeSend: true,
            proposeSendContextExperimental: true,
            sendProposalPrompter: { _ in .cancel }
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(
                    """
                    {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"propose_send","arguments":{"to":["a@b.c"],"subject":"Hi","body":"Hello","context":{"casePath":"../escape","events":[]}}}}
                    """.utf8
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("relative path") || response.body.contains("casePath"))
    }

    @Test func awaitProposeSendReturnsOpenedInMailOutcome() async throws {
        let outgoing = FakeMailOutgoingSender()
        let env = try LoopbackFixture(
            mailOutgoingSender: outgoing,
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in .openInMail }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "alex@example.com", "subject": "Hi", "body": "Hello"]
        )
        let proposalId = try #require(ack["proposalId"] as? String)
        let payload = try await Self.awaitProposeSendPayload(
            env.server,
            credential: env.credential,
            proposalId: proposalId
        )
        #expect(payload["outcome"] as? String == "opened_in_mail")
        #expect(outgoing.deliveries[0].mode == .visibleCompose)
    }

    @Test func awaitProposeSendReturnsCancelledOutcome() async throws {
        let outgoing = FakeMailOutgoingSender()
        let env = try LoopbackFixture(
            mailOutgoingSender: outgoing,
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in .cancel }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "alex@example.com", "subject": "Hi", "body": "Hello"]
        )
        let proposalId = try #require(ack["proposalId"] as? String)
        let payload = try await Self.awaitProposeSendPayload(
            env.server,
            credential: env.credential,
            proposalId: proposalId
        )
        #expect(payload["outcome"] as? String == "cancelled")
        #expect(outgoing.deliveries.isEmpty)
    }

    @Test func awaitProposeSendFailsAfterSendWhenScriptingThrows() async throws {
        let outgoing = FakeMailOutgoingSender(error: .scriptFailed("Mail refused"))
        let env = try LoopbackFixture(
            mailOutgoingSender: outgoing,
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "alex@example.com", "subject": "Hi", "body": "Hello"]
        )
        let proposalId = try #require(ack["proposalId"] as? String)
        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: try Self.toolCallJSONObject(
                    name: "await_propose_send",
                    arguments: ["proposalId": proposalId, "timeout": 5]
                )
            )
        )

        #expect(response.body.contains("isError"))
        #expect(response.body.contains("Mail refused"))
        #expect(outgoing.deliveries.count == 1)
        #expect(env.audit.entries().contains {
            $0.kind == .awaitProposeSend && $0.outcome != .ok
        })
    }

    @Test func awaitProposeSendAfterFailedDeliverDoesNotReportBareSendOnRetry() async throws {
        let outgoing = FakeMailOutgoingSender(error: .scriptFailed("Mail refused"))
        let env = try LoopbackFixture(
            mailOutgoingSender: outgoing,
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "alex@example.com", "subject": "Hi", "body": "Hello"]
        )
        let proposalId = try #require(ack["proposalId"] as? String)

        let first = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: try Self.toolCallJSONObject(
                    name: "await_propose_send",
                    arguments: ["proposalId": proposalId, "timeout": 5]
                )
            )
        )
        #expect(first.body.contains("isError"))
        #expect(outgoing.deliveries.count == 1)

        // Claim must not stick after failure — a bare `outcome: send` without a second
        // deliver would lie that Apple Mail accepted the message.
        let second = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: try Self.toolCallJSONObject(
                    name: "await_propose_send",
                    arguments: ["proposalId": proposalId, "timeout": 5]
                )
            )
        )
        if !second.body.contains("isError") {
            let payload = try Self.toolPayload(second.body)
            #expect(payload["outcome"] as? String != "send")
        }
        #expect(outgoing.deliveries.count >= 1)
        // Still failing (error uncleared): either error again or retry attempt; never silent success.
        #expect(second.body.contains("isError") || second.body.contains("Mail refused"))
    }

    @Test func awaitProposeSendRetriesDeliverAfterPriorFailure() async throws {
        let outgoing = FakeMailOutgoingSender(error: .scriptFailed("Mail refused"))
        let env = try LoopbackFixture(
            mailOutgoingSender: outgoing,
            agentMayProposeSend: true,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: ["to": "alex@example.com", "subject": "Hi", "body": "Hello"]
        )
        let proposalId = try #require(ack["proposalId"] as? String)

        let first = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: try Self.toolCallJSONObject(
                    name: "await_propose_send",
                    arguments: ["proposalId": proposalId, "timeout": 5]
                )
            )
        )
        #expect(first.body.contains("isError"))
        #expect(outgoing.deliveries.count == 1)

        outgoing.error = nil
        let payload = try await Self.awaitProposeSendPayload(
            env.server,
            credential: env.credential,
            proposalId: proposalId
        )
        #expect(payload["outcome"] as? String == "send")
        #expect(outgoing.deliveries.count == 2)
    }

    @Test func proposeSendRejectsEmptyPlacementSenderWhenRevealOff() async throws {
        let outgoing = FakeMailOutgoingSender()
        let env = try ProposeSendIdentityFixture(
            mailOutgoingSender: outgoing,
            revealAccountsWithNoPlacements: false,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "propose_send",
                    arguments: [
                        "to": "alex@example.com",
                        "subject": "Hi",
                        "body": "Hello",
                        "sender": env.emailB.uppercased()
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("list_accounts"))
        #expect(response.body.contains(env.emailA))
        #expect(!response.body.contains(env.emailB))
        #expect(outgoing.deliveries.isEmpty)
    }

    @Test func proposeSendAllowsSenderFromEmptyPlacementAccountWhenRevealOn() async throws {
        let outgoing = FakeMailOutgoingSender()
        let env = try ProposeSendIdentityFixture(
            mailOutgoingSender: outgoing,
            revealAccountsWithNoPlacements: true,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: [
                "to": "alex@example.com",
                "subject": "Hi",
                "body": "Hello",
                "sender": env.emailB.uppercased()
            ]
        )
        let proposalId = try #require(ack["proposalId"] as? String)
        _ = try await Self.awaitProposeSendPayload(
            env.server,
            credential: env.credential,
            proposalId: proposalId
        )
        #expect(outgoing.deliveries.count == 1)
        #expect(outgoing.deliveries[0].proposal.sender == env.emailB.uppercased())
    }

    @Test func proposeSendAllowsGmailDotEquivalentSender() async throws {
        let outgoing = FakeMailOutgoingSender()
        let env = try ProposeSendIdentityFixture(
            mailOutgoingSender: outgoing,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        // list_accounts has marotron@gmail.com; dotted form is the same Gmail mailbox.
        let ack = try await Self.proposeSendAck(
            env.server,
            credential: env.credential,
            arguments: [
                "to": "alex@example.com",
                "subject": "Hi",
                "body": "Hello",
                "sender": "m.arotron@gmail.com"
            ]
        )
        let proposalId = try #require(ack["proposalId"] as? String)
        _ = try await Self.awaitProposeSendPayload(
            env.server,
            credential: env.credential,
            proposalId: proposalId
        )
        #expect(outgoing.deliveries.count == 1)
        #expect(outgoing.deliveries[0].proposal.sender == "m.arotron@gmail.com")
    }

    @Test func proposeSendRejectsUnknownSender() async throws {
        let outgoing = FakeMailOutgoingSender()
        let env = try ProposeSendIdentityFixture(
            mailOutgoingSender: outgoing,
            sendProposalPrompter: { _ in .send }
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "propose_send",
                    arguments: [
                        "to": "alex@example.com",
                        "subject": "Hi",
                        "body": "Hello",
                        "sender": "nobody@example.com"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(response.body.contains("isError"))
        #expect(response.body.contains("list_accounts"))
        #expect(response.body.contains(env.emailA))
        #expect(outgoing.deliveries.isEmpty)
    }

    @Test func listAccountsOmitsEmptyPlacementsByDefault() async throws {
        let env = try ProposeSendIdentityFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            sendProposalPrompter: { _ in .cancel }
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_accounts","arguments":{}}}"#.utf8)
            )
        )

        #expect(response.status == 200)
        #expect(!response.body.contains("isError"))
        let payload = try Self.toolPayload(response.body)
        let accounts = payload["accounts"] as? [[String: Any]]
        #expect(accounts?.count == 1)
        let byEmail = Dictionary(
            uniqueKeysWithValues: (accounts ?? []).compactMap { row -> (String, [String])? in
                guard let email = row["email"] as? String,
                      let placements = row["placements"] as? [String]
                else { return nil }
                return (email, placements)
            }
        )
        #expect(byEmail[env.emailA] == ["INBOX"])
        #expect(byEmail[env.emailB] == nil)
        #expect(env.audit.entries().contains { $0.kind == .listAccounts })
    }

    @Test func listAccountsIncludesEmptyPlacementsWhenRevealOn() async throws {
        let env = try ProposeSendIdentityFixture(
            mailOutgoingSender: FakeMailOutgoingSender(),
            revealAccountsWithNoPlacements: true,
            sendProposalPrompter: { _ in .cancel }
        )
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Data(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_accounts","arguments":{}}}"#.utf8)
            )
        )

        #expect(response.status == 200)
        #expect(!response.body.contains("isError"))
        let payload = try Self.toolPayload(response.body)
        let accounts = payload["accounts"] as? [[String: Any]]
        #expect(accounts?.count == 2)
        let byEmail = Dictionary(
            uniqueKeysWithValues: (accounts ?? []).compactMap { row -> (String, [String])? in
                guard let email = row["email"] as? String,
                      let placements = row["placements"] as? [String]
                else { return nil }
                return (email, placements)
            }
        )
        #expect(byEmail[env.emailA] == ["INBOX"])
        #expect(byEmail[env.emailB] == [])
        #expect(env.audit.entries().contains { $0.kind == .listAccounts })
    }

    @Test func authenticatedGetAttachmentReturnsPathJSON() async throws {
        let env = try AttachmentLoopbackFixture(attachmentContent: true)
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "get_attachment",
                    arguments: [
                        "accountID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        "placement": "INBOX",
                        "id": "1",
                        "filename": "statement.pdf"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(!response.body.contains("isError"))
        let payload = try Self.toolPayload(response.body)
        #expect(payload["attachmentContentAccess"] as? String == "granted")
        let path = try #require(payload["path"] as? String)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == env.pdfBytes)
        let attach = try #require(env.audit.entries().last { $0.kind == .getAttachment })
        let auditJSON = jsonObject(attach.responseSummary)
        #expect(auditJSON["path"] as? String == "statement.pdf")
        #expect(attach.messages.first?.fields.attachmentContent == true)
    }

    @Test func getAttachmentDeniedContentReturnsNotGrantedWithoutIsError() async throws {
        let env = try AttachmentLoopbackFixture(attachmentContent: false)
        defer { env.remove() }

        let response = await env.server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(env.credential)"],
                body: Self.toolCallJSON(
                    name: "get_attachment",
                    arguments: [
                        "accountID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                        "placement": "INBOX",
                        "id": "1",
                        "filename": "statement.pdf"
                    ]
                )
            )
        )

        #expect(response.status == 200)
        #expect(!response.body.contains("isError"))
        let payload = try Self.toolPayload(response.body)
        #expect(payload["attachmentContentAccess"] as? String == "not_granted")
        #expect(payload["path"] == nil)
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

        let versions = try env.server.host.ledger.list(draftID: draftID)
        #expect(versions.map(\.label) == ["v2", "v1"])
        #expect(try env.server.host.ledger.copy(versionID: versions[0].id) == "Hello Ava — revised")
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

    private static func toolCallJSONObject(name: String, arguments: [String: Any]) throws -> Data {
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": arguments
            ]
        ]
        return try JSONSerialization.data(withJSONObject: envelope)
    }

    private static func proposeSendAck(
        _ server: LoopbackMCPServer,
        credential: String,
        arguments: [String: Any]
    ) async throws -> [String: Any] {
        let response = await server.handle(
            LoopbackMCPRequest(
                method: "POST",
                path: "/mcp",
                headers: ["Authorization": "Bearer \(credential)"],
                body: try toolCallJSONObject(name: "propose_send", arguments: arguments)
            )
        )
        #expect(!response.body.contains("isError"))
        return try toolPayload(response.body)
    }

    private static func awaitProposeSendPayload(
        _ server: LoopbackMCPServer,
        credential: String,
        proposalId: String,
        timeout: Double = 5
    ) async throws -> [String: Any] {
        // Prompter runs in a fire-and-forget Task after propose_send ack.
        for _ in 0..<40 {
            let response = await server.handle(
                LoopbackMCPRequest(
                    method: "POST",
                    path: "/mcp",
                    headers: ["Authorization": "Bearer \(credential)"],
                    body: try toolCallJSONObject(
                        name: "await_propose_send",
                        arguments: ["proposalId": proposalId, "timeout": timeout]
                    )
                )
            )
            if response.body.contains("isError") {
                return try toolPayload(response.body)
            }
            let payload = try toolPayload(response.body)
            if payload["outcome"] != nil {
                return payload
            }
            // Soft still-awaiting: brief pause then retry.
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
        throw DraftLedgerError.notFound
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
    let pairing: Pairing
    let grants: GrantGate
    let server: LoopbackMCPServer

    init(
        bodyGranted: Bool = true,
        sourceController: (any MailSourceControlling)? = nil,
        appleMailOpener: (any AppleMailOpening)? = nil,
        agentMayOpenInMail: Bool = false,
        mailOutgoingSender: (any MailOutgoingSending)? = nil,
        agentMayProposeSend: Bool = false,
        proposeSendContextExperimental: Bool = false,
        sendProposalPrompter: (@Sendable (SendProposal) async -> SendProposalDecision)? = nil,
        internetMessageID: String? = nil,
        subject: String = "Invoice due",
        body: String = "Please pay",
        leakGuard: OutboundLeakGuard = OutboundLeakGuard()
    ) throws {
        root = try FixtureTree()
        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let messageIDHeader = internetMessageID.map { "Message-ID: \($0)\n" } ?? ""
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Cc: Finance <finance@example.com>
            Subject: \(subject)
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            \(messageIDHeader)Content-Type: text/plain

            \(body)
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-mcp-\(UUID().uuidString).sqlite")
        let index = try MailboxIndex(store: MailStore(root: root.mail), databaseURL: db)
        _ = try index.ingest()

        audit = AuditLog()
        pairing = Pairing(audit: audit)
        let agent = try pairing.register(
            name: "Cursor",
            trustClass: .machineLocal,
            credential: credential
        )
        grants = GrantGate()
        try grants.allow(
            agentID: agent.id,
            accountID: accountID,
            fields: GrantFields(envelope: true, body: bodyGranted)
        )
        let gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            leakGuard: leakGuard,
            audit: audit
        )
        server = LoopbackMCPServer(
            gateway: gateway,
            sourceController: sourceController,
            appleMailOpener: appleMailOpener,
            agentMayOpenInMail: agentMayOpenInMail,
            mailOutgoingSender: mailOutgoingSender,
            agentMayProposeSend: agentMayProposeSend,
            proposeSendContextExperimental: proposeSendContextExperimental,
            sendProposalPrompter: sendProposalPrompter
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
    }
}

/// Two accounts; only A is granted. B has empty placements unless reveal is on.
private struct ProposeSendIdentityFixture {
    let root: FixtureTree
    let db: URL
    let accountsDB: URL
    let credential = "secret-token"
    let accountA = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
    let accountB = "BBBBBBBB-CCCC-DDDD-EEEE-FFFFFFFFFFFF"
    let emailA = "marotron@gmail.com"
    let emailB = "nite.ma.roux@gmail.com"
    let audit: AuditLog
    let server: LoopbackMCPServer

    init(
        mailOutgoingSender: (any MailOutgoingSending)?,
        revealAccountsWithNoPlacements: Bool = false,
        sendProposalPrompter: (@Sendable (SendProposal) async -> SendProposalDecision)?
    ) throws {
        root = try FixtureTree()
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
            account: accountA,
            mailbox: "INBOX.mbox"
        )
        try root.writeEmlx(
            named: "2.emlx",
            rfc822: """
            From: Other <other@example.com>
            To: Bob <bob@example.com>
            Subject: Other
            Date: Tue, 2 Jan 2024 00:00:00 +0000
            Content-Type: text/plain

            hi
            """,
            account: accountB,
            mailbox: "INBOX.mbox"
        )

        accountsDB = try Self.writeAccountsDatabase([
            (id: accountA, displayName: "Maro - gmail", email: emailA),
            (id: accountB, displayName: "MaRoux - gmail", email: emailB),
        ])

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-mcp-send-\(UUID().uuidString).sqlite")
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
        try grants.allow(agentID: agent.id, accountID: accountA)
        let gateway = AgentReadAPI(
            read: ReadAPI(index: index),
            pairing: pairing,
            grants: grants,
            audit: audit,
            accountsDatabases: [accountsDB]
        )
        server = LoopbackMCPServer(
            gateway: gateway,
            mailOutgoingSender: mailOutgoingSender,
            agentMayProposeSend: true,
            revealAccountsWithNoPlacements: revealAccountsWithNoPlacements,
            sendProposalPrompter: sendProposalPrompter
        )
    }

    func remove() {
        root.remove()
        try? FileManager.default.removeItem(at: db)
        try? FileManager.default.removeItem(at: accountsDB)
    }

    private static func writeAccountsDatabase(
        _ rows: [(id: String, displayName: String, email: String)]
    ) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Accounts-\(UUID().uuidString).sqlite")
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw NSError(domain: "ProposeSendIdentityFixture", code: 1)
        }
        defer { sqlite3_close(db) }
        guard sqlite3_exec(
            db,
            """
            CREATE TABLE ZACCOUNT (
              ZIDENTIFIER TEXT,
              ZACCOUNTDESCRIPTION TEXT,
              ZUSERNAME TEXT
            );
            """,
            nil,
            nil,
            nil
        ) == SQLITE_OK else {
            throw NSError(domain: "ProposeSendIdentityFixture", code: 2)
        }
        for row in rows {
            let sql = """
            INSERT INTO ZACCOUNT (ZIDENTIFIER, ZACCOUNTDESCRIPTION, ZUSERNAME)
            VALUES ('\(row.id)', '\(row.displayName)', '\(row.email)');
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw NSError(domain: "ProposeSendIdentityFixture", code: 3)
            }
        }
        return url
    }
}

private struct AttachmentLoopbackFixture {
    let root: FixtureTree
    let db: URL
    let credential = "secret-token"
    let pdfBytes = Data("%PDF-1.4\nattachment-bytes".utf8)
    let audit: AuditLog
    let server: LoopbackMCPServer

    init(attachmentContent: Bool) throws {
        root = try FixtureTree()
        let accountID = "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"
        let pdfB64 = pdfBytes.base64EncodedString()
        try root.writeEmlx(
            named: "1.emlx",
            rfc822: """
            From: Alice <alice@example.com>
            To: Bob <bob@example.com>
            Subject: Statement
            Date: Mon, 1 Jan 2024 00:00:00 +0000
            MIME-Version: 1.0
            Content-Type: multipart/mixed; boundary="MIX"

            --MIX
            Content-Type: text/plain; charset=utf-8

            See statement.

            --MIX
            Content-Type: application/pdf; name="statement.pdf"
            Content-Disposition: attachment; filename="statement.pdf"
            Content-Transfer-Encoding: base64

            \(pdfB64)
            --MIX--
            """,
            account: accountID,
            mailbox: "INBOX.mbox"
        )

        db = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-mcp-attach-\(UUID().uuidString).sqlite")
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
            fields: GrantFields(
                envelope: true,
                body: true,
                attachmentMetadata: true,
                attachmentContent: attachmentContent
            )
        )
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

private final class FakeAppleMailOpener: AppleMailOpening, @unchecked Sendable {
    var openedIDs: [String] = []
    var result: Bool

    init(result: Bool) {
        self.result = result
    }

    func openMessage(internetMessageID: String) -> Bool {
        openedIDs.append(internetMessageID)
        return result
    }
}

private final class ProposalCaptureBox: @unchecked Sendable {
    var value: SendProposal?
}

private final class FakeMailOutgoingSender: MailOutgoingSending, @unchecked Sendable {
    struct Delivery: Equatable {
        let proposal: SendProposal
        let mode: MailOutgoingMode
    }

    var deliveries: [Delivery] = []
    var error: MailOutgoingError?

    init(error: MailOutgoingError? = nil) {
        self.error = error
    }

    func deliver(_ proposal: SendProposal, mode: MailOutgoingMode) throws {
        deliveries.append(Delivery(proposal: proposal, mode: mode))
        if let error { throw error }
    }
}
