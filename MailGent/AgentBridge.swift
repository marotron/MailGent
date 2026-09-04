import Foundation
import MailStore
import Observation

/// Machine-local pairing presets shown as half-width companion cards.
enum AgentPairingPreset: String, CaseIterable, Identifiable {
    case cursor = "Cursor"
    case grok = "Grok Bot"

    var id: String { rawValue }
    var displayName: String { rawValue }
}

struct PairedAgentCredential: Identifiable, Equatable {
    let id: String
    let name: String
    let trustClass: AgentTrustClass
    let credential: String

    var pairedAgent: PairedAgent {
        PairedAgent(id: id, name: name, trustClass: trustClass)
    }
}

/// First-ship agent pairing + audit surface for the companion control center.
@MainActor
@Observable
final class AgentBridge {
    let audit = AuditLog(fileURL: AgentBridge.auditFileURL)
    let pairing: Pairing
    let grants = GrantGate()
    let ledger = DraftLedger()

    private(set) var pairedAgents: [PairedAgentCredential] = []
    private(set) var selectedAgentID: String?
    private(set) var isListening = false
    private(set) var listenNote = "Loopback MCP not bound yet"
    /// Bumped whenever grants change so SwiftUI refreshes checkbox state.
    private(set) var grantRevision = 0
    /// Bumped on each audit append so menu / detail refresh without waiting for Timeline.
    private(set) var auditRevision = 0
    /// Status-item pulse for the latest agent request (success / error linger + fade).
    private(set) var iconPulse = MenuBarIconPulse()
    /// Observable mirror of GrantGate rows for the selected agent (UI source of truth).
    private(set) var grantRows: [Grant] = []
    /// On-device outbound leak guard policy (loaded from sensitive-filter.json).
    private(set) var leakGuardPolicy: OutboundLeakGuardPolicy = .default
    /// Bumped when leak guard policy changes so SwiftUI refreshes toggles.
    private(set) var leakGuardRevision = 0
    var loopbackURL: String { MailGentPreferences.loopbackURL }
    private var loopbackPort: UInt16 { MailGentPreferences.loopbackPort }
    private var http: LoopbackHTTPListener?
    private var loopbackHost: LoopbackHost?
    private var lastPulsedRequestID: String?
    private var pulseClearTask: Task<Void, Never>?

    var selectedAgent: PairedAgent? {
        pairedAgents.first { $0.id == selectedAgentID }?.pairedAgent
            ?? pairedAgents.first?.pairedAgent
    }

    var selectedCredential: String? {
        pairedAgents.first { $0.id == selectedAgentID }?.credential
            ?? pairedAgents.first?.credential
    }

    /// Menu / status label: selected name, or `N agents` when more than one is paired.
    var connectedAgentLabel: String {
        switch pairedAgents.count {
        case 0: return "—"
        case 1: return pairedAgents[0].name
        default: return "\(pairedAgents.count) agents"
        }
    }

    func pairedCredential(named name: String) -> PairedAgentCredential? {
        pairedAgents.first {
            $0.name.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    func isPaired(named name: String) -> Bool {
        pairedCredential(named: name) != nil
    }

    func grantCount(for agentID: String) -> Int {
        grants.list(agentID: agentID).count
    }

    var allAudit: [AuditEntry] {
        _ = auditRevision
        return Array(audit.entries().reversed())
    }

    /// Newest tool call that counts as an agent request (excludes pair / revoke).
    var lastAgentRequest: AuditEntry? {
        _ = auditRevision
        return audit.entries().reversed().first { Self.isAgentRequest($0.kind) }
    }

    static func isAgentRequest(_ kind: AuditKind) -> Bool {
        switch kind {
        case .search, .list, .listNew, .listPlacements, .get, .createDraft, .updateDraft, .updateIndex, .status,
            .setSource:
            return true
        case .pair, .revoke:
            return false
        }
    }

    func noteAuditChanged() {
        auditRevision &+= 1
        guard
            let entry = lastAgentRequest,
            entry.id != lastPulsedRequestID
        else { return }
        lastPulsedRequestID = entry.id
        let hold: TimeInterval
        switch entry.outcome {
        case .ok:
            var next = iconPulse
            next.recordSuccess()
            iconPulse = next
            hold = MenuBarIconPulse.successHold
        case .error:
            var next = iconPulse
            next.recordError()
            iconPulse = next
            hold = MenuBarIconPulse.errorHold
        }
        pulseClearTask?.cancel()
        pulseClearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(hold))
            guard !Task.isCancelled else { return }
            self?.iconPulse = MenuBarIconPulse()
        }
    }

    func configSnippet(for credential: String) -> String {
        """
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

    func configSnippet(for agent: PairedAgentCredential) -> String {
        configSnippet(for: agent.credential)
    }

    /// Selected agent's Bearer MCP snippet (Grant Desk / legacy call sites).
    var cursorConfigSnippet: String {
        guard let credential = selectedCredential else {
            return "Pair an agent to generate an MCP snippet."
        }
        return configSnippet(for: credential)
    }

    init() {
        pairing = Pairing(audit: audit)
        audit.policy = MailGentPreferences.auditRetention
        audit.onChange = { [weak self] in
            Task { @MainActor in
                self?.noteAuditChanged()
            }
        }
        audit.applyRetention()
        restorePersistedPairing()
        restorePersistedLeakGuardPolicy()
    }

    var leakGuardEnabled: Bool {
        get { leakGuardPolicy.enabled }
        set { setLeakGuardEnabled(newValue) }
    }

    var customLeakRules: [CustomLeakRule] {
        leakGuardPolicy.customRules
    }

    func setLeakGuardEnabled(_ enabled: Bool) {
        guard leakGuardPolicy.enabled != enabled else { return }
        leakGuardPolicy.enabled = enabled
        persistLeakGuardPolicy()
    }

    func isScopeProtected(accountID: String, placement: String) -> Bool {
        leakGuardPolicy.isScopeProtected(accountID: accountID, placement: placement)
    }

    func isScopeInLeakGuardAllowlist(accountID: String, placement: String?) -> Bool {
        let key = OutboundLeakGuardPolicy.scopeKey(accountID: accountID, placement: placement)
        return leakGuardPolicy.scopes.contains(key)
    }

    func toggleLeakGuardScope(accountID: String, placement: String?) {
        let key = OutboundLeakGuardPolicy.scopeKey(accountID: accountID, placement: placement)
        if leakGuardPolicy.scopes.contains(key) {
            leakGuardPolicy.scopes.remove(key)
        } else {
            leakGuardPolicy.scopes.insert(key)
        }
        persistLeakGuardPolicy()
    }

    func setBuiltInLeakClass(_ leakClass: BuiltInLeakClass, enabled: Bool) {
        guard leakGuardPolicy.builtInClasses[leakClass] != enabled else { return }
        leakGuardPolicy.builtInClasses[leakClass] = enabled
        persistLeakGuardPolicy()
    }

    func setSubjectHitMode(_ mode: LeakGuardHitMode) {
        guard leakGuardPolicy.subjectHitMode != mode else { return }
        leakGuardPolicy.subjectHitMode = mode
        persistLeakGuardPolicy()
    }

    func setBodyHitMode(_ mode: LeakGuardHitMode) {
        guard leakGuardPolicy.bodyHitMode != mode else { return }
        leakGuardPolicy.bodyHitMode = mode
        persistLeakGuardPolicy()
    }

    func addCustomLeakRule(_ rule: CustomLeakRule) {
        leakGuardPolicy.customRules.append(rule)
        persistLeakGuardPolicy()
    }

    func updateCustomLeakRule(_ rule: CustomLeakRule) {
        guard let index = leakGuardPolicy.customRules.firstIndex(where: { $0.id == rule.id }) else { return }
        leakGuardPolicy.customRules[index] = rule
        persistLeakGuardPolicy()
    }

    func removeCustomLeakRule(id: String) {
        let before = leakGuardPolicy.customRules.count
        leakGuardPolicy.customRules.removeAll { $0.id == id }
        guard leakGuardPolicy.customRules.count != before else { return }
        persistLeakGuardPolicy()
    }

    func moveCustomLeakRules(from source: IndexSet, to destination: Int) {
        leakGuardPolicy.customRules.move(fromOffsets: source, toOffset: destination)
        persistLeakGuardPolicy()
    }

    var auditStoredCount: Int {
        _ = auditRevision
        return audit.entries().count
    }

    var auditStoredBytes: Int {
        _ = auditRevision
        return audit.byteCount()
    }

    func applyAuditRetention() {
        audit.policy = MailGentPreferences.auditRetention
        audit.applyRetention()
    }

    var hasAuditOlderThan24Hours: Bool {
        _ = auditRevision
        let cutoff = Date().addingTimeInterval(-86_400)
        return audit.entries().contains { $0.at < cutoff }
    }

    func removeAllAudit() {
        audit.removeAll()
    }

    func removeAuditOlderThan24Hours() {
        audit.removeOlderThan(Date().addingTimeInterval(-86_400))
    }

    /// Auto-pair Cursor only when nothing is persisted yet. Never auto-pairs Grok Bot.
    func ensureMachineLocalAgent() {
        guard pairedAgents.isEmpty else { return }
        _ = pairAgent(named: AgentPairingPreset.cursor.displayName)
    }

    @discardableResult
    func pairAgent(named name: String) -> PairedAgentCredential? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isPaired(named: trimmed) {
            MailGentLog.trace("agent pair refused: duplicate name \(trimmed)")
            return pairedCredential(named: trimmed)
        }
        let token = Self.makeCredential()
        do {
            let paired = try pairing.register(
                name: trimmed,
                trustClass: .machineLocal,
                credential: token
            )
            let row = PairedAgentCredential(
                id: paired.id,
                name: paired.name,
                trustClass: paired.trustClass,
                credential: token
            )
            pairedAgents.append(row)
            selectedAgentID = row.id
            persistPairing()
            persistGrants()
            refreshGrantRows()
            if Self.isCursorName(row.name) {
                syncCursorMCPConfig()
            }
            return row
        } catch {
            MailGentLog.trace("agent pair failed: \(error)")
            return nil
        }
    }

    func selectAgent(id: String?) {
        guard id != selectedAgentID else { return }
        if isEditingGrants {
            cancelGrantDeskEdits()
        }
        selectedAgentID = id
        persistPairing()
        refreshGrantRows()
    }

    func selectAgent(named name: String) {
        guard let row = pairedCredential(named: name) else { return }
        selectAgent(id: row.id)
    }

    /// Optional From filter applied to new allows until cleared (ticket 03 minimal UI).
    var draftFromFilter = ""
    /// Optional ISO8601 lower bound for new allows.
    var draftDateStart = ""
    /// When true, the next mailbox checkbox writes a deny carve-out instead of an allow.
    var draftDenyMode = false
    /// Access tab selection: grant identity key `mode|accountID|placementOr*`.
    var selectedAccessKey: String?
    /// Grant desk Scope/Access stay view-only until the human clicks Edit.
    private(set) var isEditingGrants = false
    /// Rows + draft filters captured at Edit; Cancel restores this snapshot.
    private var grantDeskEditBaseline: GrantDeskEditBaseline?
    /// While editing, GrantGate updates stay in memory until Save.
    private var grantDeskPersistDeferred = false

    func beginGrantDeskEdits() {
        guard !isEditingGrants else { return }
        grantDeskEditBaseline = GrantDeskEditBaseline(
            rows: grantRows,
            fromFilter: draftFromFilter,
            dateStart: draftDateStart,
            denyMode: draftDenyMode,
            selectedAccessKey: selectedAccessKey,
            leakGuardPolicy: leakGuardPolicy
        )
        grantDeskPersistDeferred = true
        isEditingGrants = true
        grantRevision += 1
    }

    func commitGrantDeskEdits() {
        guard isEditingGrants else { return }
        grantDeskPersistDeferred = false
        grantDeskEditBaseline = nil
        isEditingGrants = false
        persistGrants()
        persistLeakGuardPolicy()
    }

    func cancelGrantDeskEdits() {
        guard isEditingGrants else { return }
        grantDeskPersistDeferred = false
        if let baseline = grantDeskEditBaseline {
            if let agent = selectedAgent {
                grants.replaceAll(agentID: agent.id, with: baseline.rows)
            } else {
                grantRows = baseline.rows
            }
            draftFromFilter = baseline.fromFilter
            draftDateStart = baseline.dateStart
            draftDenyMode = baseline.denyMode
            selectedAccessKey = baseline.selectedAccessKey
            leakGuardPolicy = baseline.leakGuardPolicy
            refreshGatewayLeakGuard()
        }
        grantDeskEditBaseline = nil
        isEditingGrants = false
        persistGrants()
        persistLeakGuardPolicy()
    }

    /// Adds or updates one allow and persists. Does not invent grants for new accounts.
    func allow(accountID: String, placement: String? = nil) {
        guard let agent = selectedAgent else { return }
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
        guard let agent = selectedAgent else { return }
        let kept = grants.list(agentID: agent.id).filter {
            !($0.accountID == accountID && $0.placement == placement)
        }
        grants.replaceAll(agentID: agent.id, with: kept)
        if selectedAccessKey == Self.accessKey(mode: .allow, accountID: accountID, placement: placement) {
            selectedAccessKey = nil
        }
        removeLeakGuardScope(accountID: accountID, placement: placement)
        persistGrants()
    }

    func clearGrants() {
        guard let agent = selectedAgent else { return }
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
        guard let agent = selectedAgent else { return }
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
        guard let agent = selectedAgent else { return }
        if enabled {
            let withoutAllows = grantRows.filter {
                !($0.accountID == accountID && $0.mode == .allow)
            }
            grants.replaceAll(agentID: agent.id, with: withoutAllows)
            allow(accountID: accountID, placement: nil)
        } else {
            revokeGrant(accountID: accountID, placement: nil)
        }
    }

    func setMailbox(accountID: String, placement: String, enabled: Bool) {
        guard let agent = selectedAgent else { return }
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

    func bindLoopback(
        store: MailStore,
        databaseURL: URL,
        indexUpdater: (any IndexUpdating)? = nil,
        sourceController: (any MailSourceControlling)? = nil
    ) {
        attachIndex(
            store: store,
            databaseURL: databaseURL,
            indexUpdater: indexUpdater,
            sourceController: sourceController
        )
    }

    /// Keeps the loopback port open from launch; MCP handshake works before the index is ready.
    func ensureLoopbackListening() {
        ensureMachineLocalAgent()
        let host = makeLoopbackHost()
        refreshListenNote()
        guard http == nil else { return }

        let listener = LoopbackHTTPListener(host: host, hostAddress: "127.0.0.1", port: loopbackPort)
        http = listener
        Task { @MainActor in
            do {
                try await listener.start()
                guard self.http === listener else {
                    listener.stop()
                    return
                }
                self.isListening = true
                self.refreshListenNote()
                self.syncCursorMCPConfig()
                MailGentLog.trace("mcp loopback ready \(self.loopbackURL)")
            } catch {
                self.isListening = false
                self.listenNote = "Bind failed: \(error)"
                self.http = nil
                MailGentLog.trace("mcp loopback bind failed: \(error)")
            }
        }
    }

    func updateIndexState(_ snapshot: LoopbackIndexSnapshot) {
        makeLoopbackHost().setIndexState(snapshot)
        refreshListenNote()
    }

    func setLoopbackSourceController(_ sourceController: (any MailSourceControlling)?) {
        makeLoopbackHost().setSourceController(sourceController)
    }

    func detachIndex(state: LoopbackIndexSnapshot) {
        let host = makeLoopbackHost()
        host.setGateway(nil, indexUpdater: nil)
        host.setIndexState(state)
        refreshListenNote()
    }

    func attachIndex(
        store: MailStore,
        databaseURL: URL,
        indexUpdater: (any IndexUpdating)? = nil,
        sourceController: (any MailSourceControlling)? = nil
    ) {
        ensureLoopbackListening()
        ensureMachineLocalAgent()
        let host = makeLoopbackHost()
        host.setSourceController(sourceController)
        do {
            let index = try MailboxIndex(store: store, databaseURL: databaseURL)
            let gateway = AgentReadAPI(
                read: ReadAPI(index: index),
                pairing: pairing,
                grants: grants,
                leakGuard: OutboundLeakGuard(policy: leakGuardPolicy),
                audit: audit
            )
            host.setGateway(gateway, indexUpdater: indexUpdater)
            let count = (try? gateway.read.freshness().indexedCount) ?? 0
            host.setIndexState(
                LoopbackIndexSnapshot(
                    phase: .ready,
                    indexedSoFar: count,
                    statusMessage: "Index ready"
                )
            )
            refreshListenNote()
            MailGentLog.trace("mcp index attached indexed=\(count)")
        } catch {
            host.setGateway(nil, indexUpdater: nil)
            host.setIndexState(
                LoopbackIndexSnapshot(
                    phase: .failed,
                    statusMessage: "Index attach failed: \(error)"
                )
            )
            refreshListenNote()
            MailGentLog.trace("mcp gateway open failed: \(error)")
        }
    }

    func rebindLoopbackPort() {
        stopLoopbackListener()
        ensureLoopbackListening()
    }

    private func makeLoopbackHost() -> LoopbackHost {
        if let loopbackHost { return loopbackHost }
        let host = LoopbackHost(
            pairing: pairing,
            audit: audit,
            grants: grants,
            ledger: ledger
        )
        loopbackHost = host
        return host
    }

    private func refreshListenNote() {
        guard isListening else {
            if http != nil {
                listenNote = "Starting loopback MCP…"
            } else {
                listenNote = loopbackHost?.snapshot().isReady == true
                    ? "Loopback MCP not bound yet"
                    : "Loopback MCP not bound yet"
            }
            return
        }
        let snapshot = loopbackHost?.snapshot()
        if snapshot?.phase == .indexing {
            listenNote = "Listening on \(loopbackURL) (indexing)"
        } else if snapshot?.phase == .failed {
            listenNote = "Listening on \(loopbackURL) (index failed)"
        } else if snapshot?.isReady == true {
            listenNote = "Listening on \(loopbackURL)"
        } else {
            listenNote = "Listening on \(loopbackURL) (waiting for index)"
        }
    }

    private func stopLoopbackListener() {
        http?.stop()
        http = nil
        isListening = false
    }

    func stopLoopback() {
        stopLoopbackListener()
        loopbackHost?.setGateway(nil, indexUpdater: nil)
        loopbackHost?.setIndexState(.notStarted)
        listenNote = "Loopback MCP not bound yet"
    }

    func revokeSelected() {
        guard let id = selectedAgentID ?? selectedAgent?.id else { return }
        revoke(agentID: id)
    }

    /// Revoke one agent only — no auto re-pair of anyone else.
    func revoke(agentID: String) {
        guard let index = pairedAgents.firstIndex(where: { $0.id == agentID }) else { return }
        let removed = pairedAgents[index]
        pairing.revoke(agentID: agentID)
        grants.revokeAll(agentID: agentID)
        pairedAgents.remove(at: index)

        if selectedAgentID == agentID {
            selectedAgentID = pairedAgents.first?.id
            selectedAccessKey = nil
            isEditingGrants = false
            grantDeskEditBaseline = nil
            grantDeskPersistDeferred = false
        }

        if Self.isCursorName(removed.name) {
            clearCursorMCPConfig()
        }

        if pairedAgents.isEmpty {
            clearPersistedPairing()
            clearPersistedGrants()
            grantRows = []
            grantRevision += 1
        } else {
            persistPairing()
            persistGrants()
            refreshGrantRows()
        }
    }

    /// Legacy alias used by older call sites.
    func revoke() {
        revokeSelected()
    }

    private func restorePersistedPairing() {
        guard let data = try? Data(contentsOf: Self.pairingFileURL) else { return }
        do {
            let (document, migrated) = try PersistedPairingDocument.decodeMigrating(from: data)
            var restored: [PairedAgentCredential] = []
            var renamedLegacyGrok = false
            for saved in document.agents {
                guard
                    let trust = AgentTrustClass(rawValue: saved.trustClass),
                    !saved.credential.isEmpty
                else { continue }
                let name = Self.canonicalAgentDisplayName(saved.name)
                if name != saved.name { renamedLegacyGrok = true }
                let agent = PairedAgent(id: saved.agentID, name: name, trustClass: trust)
                pairing.restore(agent: agent, credential: saved.credential)
                restored.append(
                    PairedAgentCredential(
                        id: saved.agentID,
                        name: name,
                        trustClass: trust,
                        credential: saved.credential
                    )
                )
            }
            pairedAgents = restored
            if let selected = document.selectedAgentID,
               restored.contains(where: { $0.id == selected })
            {
                selectedAgentID = selected
            } else {
                selectedAgentID = restored.first?.id
            }
            restorePersistedGrants()
            if migrated || renamedLegacyGrok {
                persistPairing()
            }
            if pairedAgents.contains(where: { Self.isCursorName($0.name) }) {
                syncCursorMCPConfig()
            }
        } catch {
            MailGentLog.trace("agent pair restore failed: \(error)")
        }
    }

    private func persistPairing() {
        guard !pairedAgents.isEmpty else {
            clearPersistedPairing()
            return
        }
        let document = PersistedPairingDocument(
            version: 2,
            agents: pairedAgents.map {
                PersistedAgentCredential(
                    agentID: $0.id,
                    name: $0.name,
                    trustClass: $0.trustClass.rawValue,
                    credential: $0.credential
                )
            },
            selectedAgentID: selectedAgentID ?? pairedAgents.first?.id
        )
        do {
            try FileManager.default.createDirectory(
                at: Self.pairingFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(document).write(to: Self.pairingFileURL, options: .atomic)
        } catch {
            MailGentLog.trace("agent pair persist failed: \(error)")
        }
    }

    private func clearPersistedPairing() {
        try? FileManager.default.removeItem(at: Self.pairingFileURL)
    }

    private func restorePersistedGrants() {
        guard
            let data = try? Data(contentsOf: Self.grantsFileURL),
            let snapshot = try? JSONDecoder().decode(GrantSnapshot.self, from: data)
        else {
            for agent in pairedAgents {
                grants.revokeAll(agentID: agent.id)
            }
            refreshGrantRows()
            return
        }
        // Preserve each grant's agentID — do not rewrite to a single selected agent.
        let byAgent = Dictionary(grouping: snapshot.grants, by: \.agentID)
        let knownIDs = Set(pairedAgents.map(\.id))
        for agentID in knownIDs {
            grants.replaceAll(agentID: agentID, with: byAgent[agentID] ?? [])
        }
        // Drop grants for agents that are no longer paired.
        for agentID in byAgent.keys where !knownIDs.contains(agentID) {
            grants.revokeAll(agentID: agentID)
        }
        refreshGrantRows()
    }

    private func persistGrants() {
        if grantDeskPersistDeferred {
            refreshGrantRows()
            return
        }
        let snapshot = GrantSnapshot(grants: grants.allGrants())
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
        if let agent = selectedAgent {
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

    private func restorePersistedLeakGuardPolicy() {
        guard
            let data = try? Data(contentsOf: Self.leakGuardPolicyFileURL),
            let saved = try? JSONDecoder().decode(OutboundLeakGuardPolicy.self, from: data)
        else {
            return
        }
        leakGuardPolicy = saved
        leakGuardRevision &+= 1
    }

    private func persistLeakGuardPolicy() {
        if grantDeskPersistDeferred {
            refreshGatewayLeakGuard()
            return
        }
        do {
            try FileManager.default.createDirectory(
                at: Self.leakGuardPolicyFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(leakGuardPolicy).write(to: Self.leakGuardPolicyFileURL, options: .atomic)
        } catch {
            MailGentLog.trace("leak guard policy persist failed: \(error)")
        }
        refreshGatewayLeakGuard()
    }

    private func removeLeakGuardScope(accountID: String, placement: String?) {
        let key = OutboundLeakGuardPolicy.scopeKey(accountID: accountID, placement: placement)
        guard leakGuardPolicy.scopes.contains(key) else { return }
        leakGuardPolicy.scopes.remove(key)
        persistLeakGuardPolicy()
    }

    private func refreshGatewayLeakGuard() {
        guard
            let host = loopbackHost,
            let existing = host.readGateway()
        else {
            leakGuardRevision &+= 1
            return
        }
        let updated = AgentReadAPI(
            read: existing.read,
            pairing: existing.pairing,
            grants: existing.grants,
            leakGuard: OutboundLeakGuard(policy: leakGuardPolicy),
            audit: existing.audit
        )
        host.setGateway(updated, indexUpdater: host.readIndexUpdater())
        leakGuardRevision &+= 1
        MailGentLog.trace(
            "leak guard policy enabled=\(leakGuardPolicy.enabled) scopes=\(leakGuardPolicy.scopes.count)"
        )
    }

    /// Keep Cursor's local MCP entry aligned with the Cursor Bearer (machine-local only).
    func syncCursorMCPConfig() {
        guard let cursor = pairedAgents.first(where: { Self.isCursorName($0.name) }) else { return }
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
        headers["Authorization"] = "Bearer \(cursor.credential)"
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

    /// Stop leaving a stale Cursor Bearer after revoke.
    private func clearCursorMCPConfig() {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/mcp.json")
        guard
            let data = try? Data(contentsOf: url),
            var root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            var servers = root["mcpServers"] as? [String: Any],
            servers["mailgent"] != nil
        else {
            return
        }
        servers.removeValue(forKey: "mailgent")
        root["mcpServers"] = servers
        guard
            let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        else {
            return
        }
        do {
            try out.write(to: url, options: .atomic)
            MailGentLog.trace("cleared Cursor mcp.json mailgent entry")
        } catch {
            MailGentLog.trace("Cursor mcp.json clear failed: \(error)")
        }
    }

    private static func isCursorName(_ name: String) -> Bool {
        name.compare("Cursor", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Maps legacy short names onto current preset display names.
    private static func canonicalAgentDisplayName(_ name: String) -> String {
        if name.compare("Grok", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
            return AgentPairingPreset.grok.displayName
        }
        return name
    }

    static var auditFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailGent", isDirectory: true)
            .appendingPathComponent("audit.json")
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

    private static var leakGuardPolicyFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailGent", isDirectory: true)
            .appendingPathComponent("sensitive-filter.json")
    }

    private static func makeCredential() -> String {
        Data((0..<24).map { _ in UInt8.random(in: 0...255) })
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private struct GrantDeskEditBaseline {
    let rows: [Grant]
    let fromFilter: String
    let dateStart: String
    let denyMode: Bool
    let selectedAccessKey: String?
    let leakGuardPolicy: OutboundLeakGuardPolicy
}
