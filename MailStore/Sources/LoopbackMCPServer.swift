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

/// Thin JSON-RPC MCP surface over AgentReadAPI (Streamable HTTP POST /mcp).
public struct LoopbackMCPServer {
    public let gateway: AgentReadAPI

    public init(gateway: AgentReadAPI) {
        self.gateway = gateway
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
            let page = try gateway.search(query, credential: credential)
            return try jsonString([
                "items": page.items.map(Self.messageSummary),
                "count": page.items.count
            ])
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
            let bodyText: String
            switch message.body {
            case .text(let text):
                bodyText = text
            case .notAvailable:
                bodyText = ""
            }
            return try jsonString([
                "id": message.id,
                "accountID": message.accountID,
                "placement": message.placement,
                "subject": message.subject,
                "from": message.from,
                "to": message.to,
                "date": message.date,
                "isPartial": message.isPartial,
                "body": bodyText
            ])
        default:
            throw CallError.unknownTool
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
                "description": "Search granted Apple Mail messages by full-text query.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "query": ["type": "string", "description": "Full-text search query"]
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
                "description": "Fetch one granted message by account, placement, and id.",
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "accountID": ["type": "string"],
                        "placement": ["type": "string"],
                        "id": ["type": "string"]
                    ],
                    "required": ["accountID", "placement", "id"]
                ]
            ]
        ]
    }
}
