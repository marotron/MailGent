import Foundation
import MailStore
import Observation

/// First-ship agent pairing + audit surface for the companion control center.
@MainActor
@Observable
final class AgentBridge {
    let audit = AuditLog()
    let pairing: Pairing
    let grants = GrantGate()

    private(set) var agent: PairedAgent?
    private(set) var credential: String?
    private(set) var isListening = false
    private(set) var listenNote = "Loopback MCP not bound yet"
    let loopbackURL = "http://127.0.0.1:8787/mcp"
    private let loopbackPort: UInt16 = 8787
    private var http: LoopbackHTTPListener?

    var recentAudit: [AuditEntry] {
        Array(audit.entries().suffix(12).reversed())
    }

    var cursorConfigSnippet: String {
        guard let credential else {
            return "Pair an agent to generate a Cursor MCP snippet."
        }
        return """
        {
          "mcpServers": {
            "mailgent": {
              "url": "\(loopbackURL)",
              "headers": {
                "Authorization": "Bearer \(credential)"
              }
            }
          }
        }
        """
    }

    init() {
        pairing = Pairing(audit: audit)
    }

    func ensureMachineLocalAgent(named name: String = "Cursor") {
        if agent != nil { return }
        let token = Self.makeCredential()
        do {
            let paired = try pairing.register(
                name: name,
                trustClass: .machineLocal,
                credential: token
            )
            agent = paired
            credential = token
        } catch {
            MailGentLog.trace("agent pair failed: \(error)")
        }
    }

    func syncGrants(accountIDs: [String]) {
        guard let agent else { return }
        grants.revokeAll(agentID: agent.id)
        for accountID in accountIDs {
            try? grants.allow(agentID: agent.id, accountID: accountID)
        }
    }

    func bindLoopback(store: MailStore, databaseURL: URL) {
        stopLoopback()
        ensureMachineLocalAgent()
        do {
            let index = try MailboxIndex(store: store, databaseURL: databaseURL)
            let gateway = AgentReadAPI(
                read: ReadAPI(index: index),
                pairing: pairing,
                grants: grants,
                audit: audit
            )
            let listener = LoopbackHTTPListener(
                gateway: gateway,
                host: "127.0.0.1",
                port: loopbackPort
            )
            http = listener
            Task { @MainActor in
                do {
                    try await listener.start()
                    guard self.http === listener else {
                        listener.stop()
                        return
                    }
                    self.isListening = true
                    self.listenNote = "Listening on \(self.loopbackURL)"
                    MailGentLog.trace("mcp loopback ready \(self.loopbackURL)")
                } catch {
                    self.isListening = false
                    self.listenNote = "Bind failed: \(error)"
                    self.http = nil
                    MailGentLog.trace("mcp loopback bind failed: \(error)")
                }
            }
        } catch {
            isListening = false
            listenNote = "Bind failed: \(error)"
            MailGentLog.trace("mcp gateway open failed: \(error)")
        }
    }

    func stopLoopback() {
        http?.stop()
        http = nil
        isListening = false
        listenNote = "Loopback MCP not bound yet"
    }

    func revoke() {
        guard let agent else { return }
        pairing.revoke(agentID: agent.id)
        grants.revokeAll(agentID: agent.id)
        self.agent = nil
        credential = nil
    }

    private static func makeCredential() -> String {
        Data((0..<24).map { _ in UInt8.random(in: 0...255) })
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
