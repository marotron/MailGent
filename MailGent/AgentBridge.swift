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
    /// Bumped whenever grants change so SwiftUI refreshes checkbox state.
    private(set) var grantRevision = 0
    /// Observable mirror of GrantGate rows for the current agent (UI source of truth).
    private(set) var grantRows: [Grant] = []
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
            // Deny-by-default: no grants until the human picks mailboxes.
            persistGrants()
            syncCursorMCPConfig()
        } catch {
            MailGentLog.trace("agent pair failed: \(error)")
        }
    }

    /// Optional From filter applied to new allows until cleared (ticket 03 minimal UI).
    var draftFromFilter = ""
    /// Optional ISO8601 lower bound for new allows.
    var draftDateStart = ""
    /// When true, the next mailbox checkbox writes a deny carve-out instead of an allow.
    var draftDenyMode = false
    /// Access tab selection: grant identity key `mode|accountID|placementOr*`.
    var selectedAccessKey: String?

    /// Adds or updates one allow and persists. Does not invent grants for new accounts.
    func allow(accountID: String, placement: String? = nil) {
        guard let agent else { return }
        var participants: [GrantParticipant] = []
        let from = draftFromFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if !from.isEmpty {
            participants.append(GrantParticipant(role: .from, address: from))
        }
        let start = draftDateStart.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = grantRows.first {
            $0.mode == .allow && $0.accountID == accountID && $0.placement == placement
        }
        try? grants.allow(
            agentID: agent.id,
            accountID: accountID,
            placement: placement,
            participants: participants,
            dateStart: start.isEmpty ? nil : start,
            dateEnd: nil,
            fields: existing?.fields ?? .headersOnly
        )
        selectedAccessKey = Self.accessKey(mode: .allow, accountID: accountID, placement: placement)
        persistGrants()
    }

    func revokeGrant(accountID: String, placement: String? = nil) {
        guard let agent else { return }
        let kept = grants.list(agentID: agent.id).filter {
            !($0.accountID == accountID && $0.placement == placement)
        }
        grants.replaceAll(agentID: agent.id, with: kept)
        if selectedAccessKey == Self.accessKey(mode: .allow, accountID: accountID, placement: placement) {
            selectedAccessKey = nil
        }
        persistGrants()
    }

    func clearGrants() {
        guard let agent else { return }
        grants.revokeAll(agentID: agent.id)
        selectedAccessKey = nil
        persistGrants()
    }

    var currentGrants: [Grant] {
        grantRows
    }

    var allowGrants: [Grant] {
        grantRows.filter { $0.mode == .allow }
    }

    static func accessKey(mode: Grant.Mode, accountID: String, placement: String?) -> String {
        "\(mode.rawValue)|\(accountID)|\(placement ?? "*")"
    }

    static func accessKey(for grant: Grant) -> String {
        accessKey(mode: grant.mode, accountID: grant.accountID, placement: grant.placement)
    }

    func selectedAccessGrant() -> Grant? {
        guard let selectedAccessKey else { return allowGrants.first }
        return grantRows.first { Self.accessKey(for: $0) == selectedAccessKey }
            ?? allowGrants.first
    }

    func selectAccessGrant(_ grant: Grant) {
        selectedAccessKey = Self.accessKey(for: grant)
        grantRevision &+= 1
    }

    /// Updates field caps on an existing allow (per-placement Access).
    func updateAllowFields(accountID: String, placement: String?, fields: GrantFields) {
        guard let agent else { return }
        guard let existing = grantRows.first(where: {
            $0.mode == .allow && $0.accountID == accountID && $0.placement == placement
        }) else { return }
        var next = fields
        if next.attachmentContent && !next.attachmentMetadata {
            next.attachmentMetadata = true
        }
        if !next.attachmentMetadata {
            next.attachmentContent = false
        }
        try? grants.allow(
            agentID: agent.id,
            accountID: accountID,
            placement: placement,
            participants: existing.participants,
            dateStart: existing.dateStart,
            dateEnd: existing.dateEnd,
            fields: next
        )
        selectedAccessKey = Self.accessKey(mode: .allow, accountID: accountID, placement: placement)
        persistGrants()
    }

    func toggleAllowField(
        accountID: String,
        placement: String?,
        keyPath: WritableKeyPath<GrantFields, Bool>
    ) {
        guard let existing = grantRows.first(where: {
            $0.mode == .allow && $0.accountID == accountID && $0.placement == placement
        }) else { return }
        var fields = existing.fields
        fields[keyPath: keyPath].toggle()
        updateAllowFields(accountID: accountID, placement: placement, fields: fields)
    }

    func hasAccountWideGrant(accountID: String) -> Bool {
        grantRows.contains {
            $0.mode == .allow && $0.accountID == accountID && $0.placement == nil
        }
    }

    func hasMailboxGrant(accountID: String, placement: String) -> Bool {
        grantRows.contains {
            $0.mode == .allow && $0.accountID == accountID && $0.placement == placement
        }
    }

    func hasMailboxDeny(accountID: String, placement: String) -> Bool {
        grantRows.contains {
            $0.mode == .deny && $0.accountID == accountID && $0.placement == placement
        }
    }

    func allowGrant(accountID: String, placement: String?) -> Grant? {
        grantRows.first {
            $0.mode == .allow && $0.accountID == accountID && $0.placement == placement
        }
    }

    /// Account-wide allow: clears per-mailbox allow rows for that account first.
    func setAccountWide(accountID: String, enabled: Bool) {
        guard agent != nil else { return }
        if enabled {
            let withoutAllows = grantRows.filter {
                !($0.accountID == accountID && $0.mode == .allow)
            }
            if let agent {
                grants.replaceAll(agentID: agent.id, with: withoutAllows)
            }
            allow(accountID: accountID, placement: nil)
        } else {
            revokeGrant(accountID: accountID, placement: nil)
        }
    }

    func setMailbox(accountID: String, placement: String, enabled: Bool) {
        guard let agent else { return }
        if draftDenyMode {
            if enabled {
                try? grants.deny(agentID: agent.id, accountID: accountID, placement: placement)
                persistGrants()
            } else {
                let kept = grantRows.filter {
                    !($0.mode == .deny && $0.accountID == accountID && $0.placement == placement)
                }
                grants.replaceAll(agentID: agent.id, with: kept)
                persistGrants()
            }
            return
        }
        if enabled {
            if hasAccountWideGrant(accountID: accountID) { return }
            allow(accountID: accountID, placement: placement)
            return
        }
        if hasAccountWideGrant(accountID: accountID) {
            // Drop account-wide; this mailbox stays off until re-checked.
            revokeGrant(accountID: accountID, placement: nil)
            return
        }
        revokeGrant(accountID: accountID, placement: placement)
    }

    func toggleAccountWide(accountID: String) {
        setAccountWide(accountID: accountID, enabled: !hasAccountWideGrant(accountID: accountID))
    }

    func toggleMailbox(accountID: String, placement: String) {
        if draftDenyMode {
            setMailbox(
                accountID: accountID,
                placement: placement,
                enabled: !hasMailboxDeny(accountID: accountID, placement: placement)
            )
            return
        }
        let on = hasAccountWideGrant(accountID: accountID)
            || hasMailboxGrant(accountID: accountID, placement: placement)
        setMailbox(accountID: accountID, placement: placement, enabled: !on)
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
        grantRows = []
        grantRevision += 1
        clearPersistedPairing()
        clearPersistedGrants()
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
        restorePersistedGrants()
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

    private func restorePersistedGrants() {
        guard let agent else { return }
        guard
            let data = try? Data(contentsOf: Self.grantsFileURL),
            let snapshot = try? JSONDecoder().decode(GrantSnapshot.self, from: data)
        else {
            grants.revokeAll(agentID: agent.id)
            refreshGrantRows()
            return
        }
        let owned = snapshot.grants.map {
            Grant(
                agentID: agent.id,
                accountID: $0.accountID,
                placement: $0.placement,
                participants: $0.participants,
                dateStart: $0.dateStart,
                dateEnd: $0.dateEnd,
                mode: $0.mode,
                fields: $0.fields
            )
        }
        grants.replaceAll(agentID: agent.id, with: owned)
        refreshGrantRows()
    }

    private func persistGrants() {
        guard let agent else { return }
        let snapshot = GrantSnapshot(grants: grants.list(agentID: agent.id))
        do {
            try FileManager.default.createDirectory(
                at: Self.grantsFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(snapshot).write(to: Self.grantsFileURL, options: .atomic)
        } catch {
            MailGentLog.trace("agent grants persist failed: \(error)")
        }
        refreshGrantRows()
    }

    private func refreshGrantRows() {
        if let agent {
            grantRows = grants.list(agentID: agent.id)
        } else {
            grantRows = []
        }
        grantRevision += 1
        MailGentLog.trace("grants rows=\(grantRows.count) rev=\(grantRevision)")
    }

    private func clearPersistedGrants() {
        try? FileManager.default.removeItem(at: Self.grantsFileURL)
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

    private static var grantsFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailGent", isDirectory: true)
            .appendingPathComponent("grants.json")
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
