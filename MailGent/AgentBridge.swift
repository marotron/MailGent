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
    let ledger = DraftLedger()

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
        restorePersistedPairing()
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
            persistPairing()
            syncCursorMCPConfig()
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
                ledger: ledger,
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
        clearPersistedPairing()
    }

    private func restorePersistedPairing() {
        guard
            let data = try? Data(contentsOf: Self.pairingFileURL),
            let saved = try? JSONDecoder().decode(PersistedPairing.self, from: data),
            let trust = AgentTrustClass(rawValue: saved.trustClass),
            !saved.credential.isEmpty
        else {
            return
        }
        let restored = PairedAgent(id: saved.agentID, name: saved.name, trustClass: trust)
        pairing.restore(agent: restored, credential: saved.credential)
        agent = restored
        credential = saved.credential
        syncCursorMCPConfig()
    }

    private func persistPairing() {
        guard let agent, let credential else { return }
        let saved = PersistedPairing(
            agentID: agent.id,
            name: agent.name,
            trustClass: agent.trustClass.rawValue,
            credential: credential
        )
        do {
            try FileManager.default.createDirectory(
                at: Self.pairingFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(saved).write(to: Self.pairingFileURL, options: .atomic)
        } catch {
            MailGentLog.trace("agent pair persist failed: \(error)")
        }
    }

    private func clearPersistedPairing() {
        try? FileManager.default.removeItem(at: Self.pairingFileURL)
    }

    /// Keep Cursor's local MCP entry aligned with the current Bearer (machine-local only).
    func syncCursorMCPConfig() {
        guard let credential else { return }
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/mcp.json")
        guard
            let data = try? Data(contentsOf: url),
            var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        var mailgent = servers["mailgent"] as? [String: Any] ?? [:]
        mailgent["url"] = loopbackURL
        var headers = mailgent["headers"] as? [String: Any] ?? [:]
        headers["Authorization"] = "Bearer \(credential)"
        mailgent["headers"] = headers
        servers["mailgent"] = mailgent
        root["mcpServers"] = servers
        guard
            let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        else {
            return
        }
        do {
            try out.write(to: url, options: .atomic)
            MailGentLog.trace("synced Cursor mcp.json Bearer")
        } catch {
            MailGentLog.trace("Cursor mcp.json sync failed: \(error)")
        }
    }

    private static var pairingFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailGent", isDirectory: true)
            .appendingPathComponent("pairing.json")
    }

    private static func makeCredential() -> String {
        Data((0..<24).map { _ in UInt8.random(in: 0...255) })
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct PersistedPairing: Codable {
    let agentID: String
    let name: String
    let trustClass: String
    let credential: String
}
