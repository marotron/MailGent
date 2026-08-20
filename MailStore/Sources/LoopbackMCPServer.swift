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

    public init(status: Int, body: String) {
        self.status = status
        self.body = body
    }
}

/// Thin JSON-RPC MCP surface over AgentReadAPI. Real Network bind comes later.
public struct LoopbackMCPServer {
    public let gateway: AgentReadAPI

    public init(gateway: AgentReadAPI) {
        self.gateway = gateway
    }

    public func handle(_ request: LoopbackMCPRequest) -> LoopbackMCPResponse {
        guard request.method.uppercased() == "POST", request.path == "/mcp" else {
            return LoopbackMCPResponse(status: 404, body: #"{"error":"not_found"}"#)
        }

        let credential = request.bearerToken
        do {
            _ = try gateway.authenticate(credential)
        } catch {
            return LoopbackMCPResponse(status: 401, body: #"{"error":"unauthorized"}"#)
        }

        guard
            let obj = try? JSONSerialization.jsonObject(with: request.body) as? [String: Any],
            let method = obj["method"] as? String,
            method == "tools/call",
            let params = obj["params"] as? [String: Any],
            let name = params["name"] as? String
        else {
            return LoopbackMCPResponse(status: 400, body: #"{"error":"bad_request"}"#)
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let id = obj["id"] ?? NSNull()

        do {
            let result: String
            switch name {
            case "search":
                let query = arguments["query"] as? String ?? ""
                let page = try gateway.search(query, credential: credential)
                let subjects = page.items.map(\.subject)
                let payload = try jsonString(["subjects": subjects])
                result = payload
            case "list":
                let page = try gateway.list(credential: credential)
                let subjects = page.items.map(\.subject)
                result = try jsonString(["subjects": subjects])
            case "listPlacements":
                let placements = try gateway.listPlacements(credential: credential)
                let rows = placements.map { "\($0.accountID)/\($0.id)" }
                result = try jsonString(["placements": rows])
            case "get":
                guard
                    let accountID = arguments["accountID"] as? String,
                    let placement = arguments["placement"] as? String,
                    let messageID = arguments["id"] as? String
                else {
                    return LoopbackMCPResponse(status: 400, body: #"{"error":"bad_request"}"#)
                }
                let message = try gateway.get(
                    credential: credential,
                    accountID: accountID,
                    placement: placement,
                    id: messageID
                )
                result = try jsonString([
                    "id": message.id,
                    "subject": message.subject,
                    "from": message.from
                ])
            default:
                return LoopbackMCPResponse(status: 400, body: #"{"error":"unknown_tool"}"#)
            }

            let envelope: [String: Any] = [
                "jsonrpc": "2.0",
                "id": id,
                "result": [
                    "content": [
                        ["type": "text", "text": result]
                    ]
                ]
            ]
            return LoopbackMCPResponse(status: 200, body: try jsonString(envelope))
        } catch PairingError.unauthorized {
            return LoopbackMCPResponse(status: 401, body: #"{"error":"unauthorized"}"#)
        } catch {
            return LoopbackMCPResponse(status: 500, body: #"{"error":"internal"}"#)
        }
    }

    private func jsonString(_ object: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
