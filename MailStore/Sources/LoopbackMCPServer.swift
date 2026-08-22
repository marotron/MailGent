import Foundation

public struct LoopbackMCPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    public init(method: String, path: String, headers: [String: String], body: Data) {
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }

    public var bearerToken: String? {
        guard let value = headers.first(where: { $0.key.lowercased() == "authorization" })?.value
        else { return nil }
        let prefix = "Bearer "
        guard value.hasPrefix(prefix) else { return nil }
        return String(value.dropFirst(prefix.count))
    }
}

public struct LoopbackMCPResponse: Sendable {
    public let status: Int
    public let body: String
    public let headers: [String: String]

    public init(status: Int, body: String, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }
}

/// Thin JSON-RPC MCP surface over AgentReadAPI + DraftLedger (Streamable HTTP POST /mcp).
public struct LoopbackMCPServer {
    public let gateway: AgentReadAPI
    public let ledger: DraftLedger
    public let indexUpdater: any IndexUpdating
    public let sourceController: (any MailSourceControlling)?

    public init(
        gateway: AgentReadAPI,
        ledger: DraftLedger = DraftLedger(),
        indexUpdater: (any IndexUpdating)? = nil,
        sourceController: (any MailSourceControlling)? = nil
    ) {
        self.gateway = gateway
        self.ledger = ledger
        self.indexUpdater = indexUpdater ?? LocalIndexUpdater(index: gateway.read.index)
        self.sourceController = sourceController
    }

    public func handle(_ request: LoopbackMCPRequest) -> LoopbackMCPResponse {
        let path = request.path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? request.path
        guard path == "/mcp" else {
            return LoopbackMCPResponse(status: 404, body: #"{"error":"not_found"}"#)
        }

        if request.method.uppercased() == "GET" {
            return LoopbackMCPResponse(status: 405, body: #"{"error":"method_not_allowed"}"#)
        }
        if request.method.uppercased() == "DELETE" {
            return LoopbackMCPResponse(status: 200, body: "", headers: ["Content-Type": "text/plain"])
        }
        guard request.method.uppercased() == "POST" else {
            return LoopbackMCPResponse(status: 405, body: #"{"error":"method_not_allowed"}"#)
        }

        let credential = request.bearerToken
        do {
            _ = try gateway.authenticate(credential)
        } catch {
            return LoopbackMCPResponse(status: 401, body: #"{"error":"unauthorized"}"#)
        }

        guard
            let obj = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
            let method = obj["method"] as? String
        else {
            return LoopbackMCPResponse(status: 400, body: #"{"error":"bad_request"}"#)
        }

        let id = obj["id"]
        let params = obj["params"] as? [String: Any] ?? [:]

        do {
            switch method {
            case "initialize":
                let protocolVersion = params["protocolVersion"] as? String ?? "2025-03-26"
                let result: [String: Any] = [
                    "protocolVersion": protocolVersion,
                    "capabilities": [
                        "tools": [:] as [String: Any]
                    ],
                    "serverInfo": [
                        "name": "mailgent",
                        "version": "0.1.0"
                    ]
                ]
                return try rpcOK(id: id ?? NSNull(), result: result)

            case "notifications/initialized", "notifications/cancelled":
                return LoopbackMCPResponse(status: 202, body: "")

            case "ping":
                return try rpcOK(id: id ?? NSNull(), result: [:] as [String: Any])

            case "tools/list":
                return try rpcOK(id: id ?? NSNull(), result: ["tools": Self.makeToolDescriptors()])

            case "tools/call":
                guard let name = params["name"] as? String else {
                    return LoopbackMCPResponse(status: 400, body: #"{"error":"bad_request"}"#)
                }
                let arguments = params["arguments"] as? [String: Any] ?? [:]
                do {
                    let text = try callTool(name: name, arguments: arguments, credential: credential)
                    let envelope: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": id ?? NSNull(),
                        "result": [
                            "content": [
                                ["type": "text", "text": text]
                            ]
                        ]
                    ]
                    return LoopbackMCPResponse(status: 200, body: try jsonString(envelope))
                } catch PairingError.unauthorized {
                    return LoopbackMCPResponse(status: 401, body: #"{"error":"unauthorized"}"#)
                } catch {
                    let envelope: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": id ?? NSNull(),
                        "result": [
                            "content": [
                                ["type": "text", "text": String(describing: error)]
                            ],
                            "isError": true
                        ]
                    ]
                    return LoopbackMCPResponse(status: 200, body: try jsonString(envelope))
                }

            default:
                return LoopbackMCPResponse(status: 400, body: #"{"error":"unknown_method"}"#)
            }
        } catch PairingError.unauthorized {
            return LoopbackMCPResponse(status: 401, body: #"{"error":"unauthorized"}"#)
        } catch {
            return LoopbackMCPResponse(status: 500, body: #"{"error":"internal"}"#)
        }
    }

    private func callTool(
        name: String,
        arguments: [String: Any],
        credential: String?
    ) throws -> String {
        switch name {
        case "search":
            let query = arguments["query"] as? String ?? ""
            let limit = Self.intArgument(arguments["limit"]) ?? 25
            let cursor = arguments["cursor"] as? String
            let page = try gateway.search(
                query,
                credential: credential,
                limit: limit,
                cursor: cursor
            )
            var payload: [String: Any] = [
                "items": page.items.map(Self.messageSummary),
                "count": page.items.count
            ]
            if let nextCursor = page.nextCursor {
                payload["nextCursor"] = nextCursor
            }
            return try jsonString(payload)
        case "list":
            let page = try gateway.list(credential: credential)
            return try jsonString([
                "items": page.items.map(Self.messageSummary),
                "count": page.items.count
            ])
        case "listPlacements":
            let placements = try gateway.listPlacements(credential: credential)
            let rows = placements.map { "\($0.accountID)/\($0.id)" }
            return try jsonString(["placements": rows])
        case "get":
            guard
                let accountID = arguments["accountID"] as? String,
                let placement = arguments["placement"] as? String,
                let messageID = arguments["id"] as? String
            else {
                throw CallError.badArguments
            }
            let message = try gateway.get(
                credential: credential,
                accountID: accountID,
                placement: placement,
                id: messageID
            )
            return try jsonString(Self.messageDetail(message))
        case "create_draft":
            let started = Date()
            let body = arguments["body"] as? String ?? ""
            let version = ledger.create(body: body)
            if let agent = try? gateway.authenticate(credential) {
                gateway.audit?.append(
                    AuditEntry(
                        kind: .createDraft,
                        agentID: agent.id,
                        agentName: agent.name,
                        detail: version.draftID,
                        at: started,
                        finishedAt: Date(),
                        requestSummary: "create_draft chars=\(body.count)",
                        responseSummary: "draftID=\(version.draftID) \(version.label)"
                    )
                )
            }
            return try jsonString(Self.versionSummary(version))
        case "update_draft":
            guard
                let draftID = arguments["draftID"] as? String,
                let body = arguments["body"] as? String
            else {
                throw CallError.badArguments
            }
            let started = Date()
            let version = try ledger.update(draftID: draftID, body: body)
            if let agent = try? gateway.authenticate(credential) {
                gateway.audit?.append(
                    AuditEntry(
                        kind: .updateDraft,
                        agentID: agent.id,
                        agentName: agent.name,
                        detail: "\(version.draftID)/\(version.label)",
                        at: started,
                        finishedAt: Date(),
                        requestSummary: "draftID=\(draftID) chars=\(body.count)",
                        responseSummary: "draftID=\(version.draftID) \(version.label)"
                    )
                )
            }
            return try jsonString(Self.versionSummary(version))
        case "status":
            let freshness = try gateway.freshness(credential: credential)
            var payload = Self.freshnessPayload(freshness)
            if let snap = sourceController?.snapshot() {
                payload["source"] = snap.source.rawValue
                payload["agentMayChangeSource"] = snap.agentMayChangeSource
            }
            return try jsonString(payload)
        case "set_source":
            return try setSource(arguments: arguments, credential: credential)
        case "update":
            let outcome = try gateway.updateIndex(credential: credential, updater: indexUpdater)
            var payload = Self.freshnessPayload(outcome.freshness)
            payload["newCount"] = outcome.newCount
            return try jsonString(payload)
        default:
            throw CallError.unknownTool
        }
    }

    private func setSource(arguments: [String: Any], credential: String?) throws -> String {
        guard let controller = sourceController else {
            throw MailSourceError.notAvailable
        }
        guard
            let raw = arguments["source"] as? String,
            let source = MailSourceID(rawValue: raw)
        else {
            throw MailSourceError.unknownSource
        }
        let started = Date()
        let agent = try gateway.authenticate(credential)
        do {
            let snap = try controller.setSource(source)
            gateway.audit?.append(
                AuditEntry(
                    kind: .setSource,
                    agentID: agent.id,
                    agentName: agent.name,
                    detail: snap.source.rawValue,
                    at: started,
                    finishedAt: Date(),
                    requestSummary: "source=\(raw)",
                    responseSummary: "source=\(snap.source.rawValue)"
                )
            )
            return try jsonString([
                "source": snap.source.rawValue,
                "agentMayChangeSource": snap.agentMayChangeSource
            ])
        } catch {
            gateway.audit?.append(
                AuditEntry(
                    kind: .setSource,
                    agentID: agent.id,
                    agentName: agent.name,
                    detail: raw,
                    at: started,
                    finishedAt: Date(),
                    requestSummary: "source=\(raw)",
                    responseSummary: String(describing: error),
                    outcome: .error(String(describing: error))
                )
            )
            throw error
        }
    }

    private static func messageSummary(_ message: IndexedMessage) -> [String: Any] {
        [
            "accountID": message.accountID,
            "placement": message.placement,
            "id": message.id,
            "subject": message.subject,
            "from": message.from,
            "date": message.date,
            "isPartial": message.isPartial
        ]
    }

    private static func intArgument(_ value: Any?) -> Int? {
        switch value {
        case let n as Int:
            return n
        case let n as NSNumber:
            return n.intValue
        case let s as String:
            return Int(s)
        default:
            return nil
        }
    }

    /// Full `get` payload. Distinguishes grant denial from empty/missing plain text.
    private static func messageDetail(_ message: ReadMessage) -> [String: Any] {
        var payload: [String: Any] = [
            "id": message.id,
            "accountID": message.accountID,
            "placement": message.placement,
            "subject": message.subject,
            "from": message.from,
            "to": message.to,
            "date": message.date,
            "isPartial": message.isPartial
        ]
        switch message.body {
        case .text(let text):
            payload["bodyAccess"] = "granted"
            payload["body"] = text
        case .notAvailable:
            payload["bodyAccess"] = "granted"
            // No plain-text body (empty or HTML-only); omit `body` rather than "".
        case .notGranted:
            payload["bodyAccess"] = "not_granted"
            payload["note"] =
                "Body omitted: the active grant for this account does not allow body access. Ask the user to enable body on the grant before summarizing or quoting the message."
        }
        return payload
    }

    private static func versionSummary(_ version: DraftVersion) -> [String: Any] {
        [
            "draftID": version.draftID,
            "versionID": version.id,
            "label": version.label,
            "body": version.body
        ]
    }

    private static func freshnessPayload(_ freshness: IndexFreshness) -> [String: Any] {
        var payload: [String: Any] = [
            "indexedCount": freshness.indexedCount
        ]
        if let lastIngestAt = freshness.lastIngestAt {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            payload["lastIngestAt"] = formatter.string(from: lastIngestAt)
        }
        if let newestMessageDate = freshness.newestMessageDate {
            payload["newestMessageDate"] = newestMessageDate
        }
        return payload
    }

    private func rpcOK(id: Any, result: [String: Any]) throws -> LoopbackMCPResponse {
        let envelope: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id,
            "result": result
        ]
        return LoopbackMCPResponse(status: 200, body: try jsonString(envelope))
    }

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private enum CallError: Error {
        case badArguments
        case unknownTool
    }

    private static func makeToolDescriptors() -> [[String: Any]] {
        [
            [
                "name": "search",
                "description":
                    "Search granted Apple Mail messages by full-text query. Results are newest-first, with subject/from matches ranked above body-only hits. Pass cursor from nextCursor to page.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Full-text search query"],
                        "limit": ["type": "integer", "description": "Page size (1–100, default 25)"],
                        "cursor": ["type": "string", "description": "Opaque page cursor from a prior nextCursor"]
                    ],
                    "required": ["query"]
                ]
            ],
            [
                "name": "list",
                "description": "List recent granted Apple Mail messages.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            ],
            [
                "name": "listPlacements",
                "description": "List granted account/mailbox placements.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            ],
            [
                "name": "get",
                "description":
                    "Fetch one granted message by account, placement, and id. Response includes bodyAccess: \"granted\" (body present or omitted when empty/HTML-only) or \"not_granted\" (grant denies body — do not treat as empty mail; ask user to enable body on the grant).",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "accountID": ["type": "string"],
                        "placement": ["type": "string"],
                        "id": ["type": "string"]
                    ],
                    "required": ["accountID", "placement", "id"]
                ]
            ],
            [
                "name": "create_draft",
                "description": "Create a MailGent-owned draft and its first version. Does not write Apple Mail.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "body": ["type": "string", "description": "Draft body text"]
                    ],
                    "required": ["body"]
                ]
            ],
            [
                "name": "update_draft",
                "description": "Append a new version to an existing MailGent draft. Does not write Apple Mail.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "draftID": ["type": "string"],
                        "body": ["type": "string", "description": "Updated draft body text"]
                    ],
                    "required": ["draftID", "body"]
                ]
            ],
            [
                "name": "status",
                "description":
                    "Index freshness: lastIngestAt, newestMessageDate, indexedCount, plus source (fixture or liveMail) and agentMayChangeSource when the companion is bound.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            ],
            [
                "name": "update",
                "description":
                    "Run an incremental ingest from Apple Mail and wait until it finishes. Returns newCount plus the same freshness fields as status.",
                "inputSchema": [
                    "type": "object",
                    "properties": [:] as [String: Any]
                ]
            ],
            [
                "name": "set_source",
                "description":
                    "Switch the companion mail source (fixture or liveMail). Denied unless enabled in MailGent Settings → General.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "source": [
                            "type": "string",
                            "description": "fixture or liveMail",
                            "enum": ["fixture", "liveMail"]
                        ]
                    ],
                    "required": ["source"]
                ]
            ]
        ]
    }
}
