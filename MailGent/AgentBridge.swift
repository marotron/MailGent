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
    /// Placeholder until NWListener binds; Cursor config uses this host/port.
    let loopbackURL = "http://127.0.0.1:8787/mcp"

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
