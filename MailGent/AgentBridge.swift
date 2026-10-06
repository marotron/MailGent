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
    let rules = RuleStore()
    let ledger = DraftLedger()

    private(set) var pairedAgents: [PairedAgentCredential] = []
    private(set) var selectedAgentID: String?
    private(set) var isListening = false
    private(set) var listenNote = "Loopback MCP not bound yet"
    /// Bumped whenever grants change so SwiftUI refreshes checkbox state.
    private(set) var grantRevision = 0
    /// Bumped whenever rule definitions or enablements change.
    private(set) var ruleRevision = 0
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
        case .search, .list, .listNew, .listPlacements, .get, .getAttachment, .openInMail, .createDraft,
            .updateDraft, .updateIndex, .status, .setSource:
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

    /// Pasteable Cursor `mcp.json` body (`mcpServers.mailgent` + Bearer).
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

    /// Control Center display — same shape as `configSnippet`, Bearer redacted.
    func displayConfigSnippet(for agent: PairedAgentCredential) -> String {
        configSnippet(for: Self.redactedBearerToken)
    }

    /// Raw pairing secret (no `Bearer ` prefix) for clipboard copy.
    func bearerString(for agent: PairedAgentCredential) -> String {
        agent.credential
    }

    private static let redactedBearerToken = "••••••••••••••••••••••••••••••••"

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
        restorePersistedRules()
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
            persistGrants(reason: .pair)
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

    /// Access tab selection: grant identity key `mode|accountID|placementOr*`.
    var selectedAccessKey: String?
    /// Grant desk Scope/Access stay view-only until the human clicks Edit.
    private(set) var isEditingGrants = false
    /// Rows captured at Edit; Cancel restores this snapshot.
    private var grantDeskEditBaseline: GrantDeskEditBaseline?
    /// While editing, GrantGate updates stay in memory until Save.
    private var grantDeskPersistDeferred = false

    func beginGrantDeskEdits() {
        guard !isEditingGrants else { return }
        grantDeskEditBaseline = GrantDeskEditBaseline(
            rows: grantRows,
            ruleSnapshot: rules.snapshot(),
            selectedAccessKey: selectedAccessKey,
            leakGuardPolicy: leakGuardPolicy
        )
        grantDeskPersistDeferred = true
        isEditingGrants = true
        grantRevision += 1
        ruleRevision += 1
    }

    func commitGrantDeskEdits() {
        guard isEditingGrants else { return }
        grantDeskPersistDeferred = false
        grantDeskEditBaseline = nil
        isEditingGrants = false
        persistGrants(reason: .save)
        persistLeakGuardPolicy()
        persistRules()
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
            rules.replace(with: baseline.ruleSnapshot)
            selectedAccessKey = baseline.selectedAccessKey
            leakGuardPolicy = baseline.leakGuardPolicy
            refreshGatewayLeakGuard()
        }
        grantDeskEditBaseline = nil
        isEditingGrants = false
        persistGrants(reason: .cancel)
        persistLeakGuardPolicy()
        persistRules()
    }

    /// Adds or updates one allow and persists. Does not invent grants for new accounts.
    func allow(accountID: String, placement: String? = nil) {
        guard let agent = selectedAgent else { return }
        let existing = grantRows.first {
            $0.mode == .allow && $0.accountID == accountID && $0.placement == placement
        }
        try? grants.allow(
            agentID: agent.id,
            accountID: accountID,
            placement: placement,
            participants: [],
            dateStart: nil,
            dateEnd: nil,
            fields: existing?.fields ?? .headersOnly
        )
        selectedAccessKey = Self.accessKey(mode: .allow, accountID: accountID, placement: placement)
        persistGrants(reason: .allow)
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
        persistGrants(reason: .revokeRow)
    }

    func clearGrants() {
        guard let agent = selectedAgent else { return }
        let before = grants.list(agentID: agent.id).count
        grants.revokeAll(agentID: agent.id)
        selectedAccessKey = nil
        MailGentLog.grantsEvent("clear agent=\(Self.shortID(agent.id)) before=\(before)")
        persistGrants(reason: .clear)
    }

    // MARK: - Rules

    var ruleDefinitions: [GrantRule] {
        _ = ruleRevision
        return rules.allRules()
    }

    /// Rules enabled on a placement for the selected agent (definitions are shared; enablements are per-agent).
    func enabledRules(accountID: String, placement: String?) -> [GrantRule] {
        _ = ruleRevision
        guard let agentID = selectedAgent?.id else { return [] }
        return rules.allRules().filter { pass in
            let exact = rules.isEnabled(
                ruleID: pass.id,
                agentID: agentID,
                accountID: accountID,
                placement: placement
            )
            if exact { return true }
            // Account-wide enablement also covers specific mailboxes.
            if placement != nil {
                return rules.isEnabled(
                    ruleID: pass.id,
                    agentID: agentID,
                    accountID: accountID,
                    placement: nil
                )
            }
            return false
        }
        .sorted { $0.nick < $1.nick }
    }

    func isRuleEnabled(ruleID: String, accountID: String, placement: String?) -> Bool {
        _ = ruleRevision
        guard let agentID = selectedAgent?.id else { return false }
        return rules.isEnabled(
            ruleID: ruleID,
            agentID: agentID,
            accountID: accountID,
            placement: placement
        )
    }

    /// Toggle exact placement enablement for the selected agent; if only inherited account-wide, clears that.
    func toggleRuleEnabled(ruleID: String, accountID: String, placement: String?) {
        guard selectedAgent?.id != nil else { return }
        let currentlyOn = enabledRules(accountID: accountID, placement: placement)
            .contains { $0.id == ruleID }
        if currentlyOn {
            if isRuleEnabled(ruleID: ruleID, accountID: accountID, placement: placement) {
                setRuleEnabled(false, ruleID: ruleID, accountID: accountID, placement: placement)
            } else if placement != nil {
                setRuleEnabled(false, ruleID: ruleID, accountID: accountID, placement: nil)
            }
        } else {
            setRuleEnabled(true, ruleID: ruleID, accountID: accountID, placement: placement)
        }
    }

    func ruleUsageCount(_ ruleID: String) -> Int {
        _ = ruleRevision
        let keys = rules.allEnablements()
            .filter { $0.ruleID == ruleID }
            .map { "\($0.accountID)|\($0.placement ?? "*")" }
        return Set(keys).count
    }

    func nextRuleNick() -> String {
        let used = Set(rules.allRules().map(\.nick))
        return (65...90).compactMap { UnicodeScalar($0).map(String.init) }.first { !used.contains($0) } ?? "Z"
    }

    func upsertRule(_ rule: GrantRule) {
        rules.upsert(rule)
        noteRulesChanged()
    }

    func deleteRule(id: String) {
        rules.removeRule(id: id)
        noteRulesChanged()
    }

    func setRuleEnabled(
        _ enabled: Bool,
        ruleID: String,
        accountID: String,
        placement: String?
    ) {
        guard let agentID = selectedAgent?.id else { return }
        rules.setEnabled(
            enabled,
            ruleID: ruleID,
            agentID: agentID,
            accountID: accountID,
            placement: placement
        )
        noteRulesChanged()
    }

    func createRuleDraft(polarity: RulePolarity = .pass) -> GrantRule {
        let isBlock = polarity == .block
        return GrantRule(
            id: "rule-\(UUID().uuidString.prefix(8))",
            name: isBlock ? "New block" : "New pass",
            nick: nextRuleNick(),
            polarity: polarity,
            fields: isBlock
                ? GrantFields(
                    subject: false,
                    from: false,
                    to: false,
                    cc: false,
                    date: false,
                    body: true,
                    attachmentMetadata: true,
                    attachmentContent: true
                )
                : GrantFields(envelope: false, body: true)
        )
    }

    private func noteRulesChanged() {
        if grantDeskPersistDeferred {
            ruleRevision &+= 1
            return
        }
        persistRules()
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
        persistGrants(reason: .fields)
    }

    /// Field caps for a mailbox row in Scope (per-mailbox grant, else inherited account-wide).
    func effectiveAllowFields(accountID: String, placement: String) -> GrantFields? {
        if let grant = allowGrant(accountID: accountID, placement: placement) {
            return grant.fields
        }
        return allowGrant(accountID: accountID, placement: nil)?.fields
    }

    func toggleAllowField(
        accountID: String,
        placement: String?,
        keyPath: WritableKeyPath<GrantFields, Bool>,
        mailboxPlacements: [String]? = nil
    ) {
        if let placement, hasAccountWideGrant(accountID: accountID) {
            materializeAccountWideToMailboxes(
                accountID: accountID,
                placements: mailboxPlacements ?? [placement]
            )
        }
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

    /// Replaces account-wide allow with one allow per mailbox, preserving caps and filters.
    private func materializeAccountWideToMailboxes(accountID: String, placements: [String]) {
        guard let agent = selectedAgent else { return }
        guard let wide = allowGrant(accountID: accountID, placement: nil) else { return }
        let mailboxPlacements = placements
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !mailboxPlacements.isEmpty else { return }

        var next = grantRows.filter {
            !($0.accountID == accountID && $0.mode == .allow)
        }
        for placement in mailboxPlacements {
            next.append(
                Grant(
                    agentID: agent.id,
                    accountID: accountID,
                    placement: placement,
                    participants: wide.participants,
                    dateStart: wide.dateStart,
                    dateEnd: wide.dateEnd,
                    mode: .allow,
                    fields: wide.fields
                )
            )
        }
        grants.replaceAll(agentID: agent.id, with: next)
        if selectedAccessKey == Self.accessKey(mode: .allow, accountID: accountID, placement: nil) {
            selectedAccessKey = nil
        }
        persistGrants(reason: .mailbox)
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
        guard selectedAgent != nil else { return }
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

    func applyAgentMayOpenInMail() {
        makeLoopbackHost().setAgentMayOpenInMail(MailGentPreferences.agentMayOpenInMail)
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
                rules: rules,
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
        host.setAppleMailOpener(WorkspaceAppleMailOpener())
        host.setAgentMayOpenInMail(MailGentPreferences.agentMayOpenInMail)
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
            clearPersistedGrants(reason: "last-agent-revoked")
            grantRows = []
            grantRevision += 1
            rules.replace(with: RuleSnapshot())
            ruleRevision += 1
            clearPersistedRules()
        } else {
            rules.removeEnablements(agentID: agentID)
            noteRulesChanged()
            persistPairing()
            persistGrants(reason: .revokeAgent, dropAgentIDs: [agentID])
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

    private enum GrantWriteReason: String {
        case pair
        case save
        case cancel
        case allow
        case revokeRow
        case clear
        case fields
        case mailbox
        case revokeAgent
    }

    private func restorePersistedGrants() {
        let disk = Self.readGrantDisk()
        let pairedIDs = pairedAgents.map(\.id)
        guard let snapshot = disk.snapshot else {
            for agent in pairedAgents {
                grants.revokeAll(agentID: agent.id)
            }
            if disk.missing {
                MailGentLog.grantsEvent("restore missing file paired=\(pairedIDs.count)")
            } else {
                MailGentLog.grantsEvent(
                    "restore decode failed bytes=\(disk.bytes) error=\(disk.error ?? "unknown") — file left untouched"
                )
            }
            refreshGrantRows()
            return
        }

        let byAgent = Dictionary(grouping: snapshot.grants, by: \.agentID)
        let knownIDs = Set(pairedIDs)
        for agentID in knownIDs {
            grants.replaceAll(agentID: agentID, with: byAgent[agentID] ?? [])
        }
        let orphanIDs = byAgent.keys.filter { !knownIDs.contains($0) }.sorted()
        let orphanCount = orphanIDs.reduce(0) { $0 + (byAgent[$1]?.count ?? 0) }
        MailGentLog.grantsEvent(
            "restore bytes=\(disk.bytes) total=\(snapshot.grants.count) loaded=\(grants.allGrants().count) orphans=\(orphanCount) \(Self.grantDigest(snapshot.grants))"
        )
        if !orphanIDs.isEmpty {
            let detail = orphanIDs.map { id in
                "\(Self.shortID(id)):\(byAgent[id]?.count ?? 0)"
            }.joined(separator: ",")
            MailGentLog.grantsEvent(
                "restore kept unpaired-agent grants on disk (\(detail)); they are not shown until that agent id is paired again"
            )
        }
        refreshGrantRows()
    }

    private func persistGrants(reason: GrantWriteReason, dropAgentIDs: Set<String> = []) {
        if grantDeskPersistDeferred {
            MailGentLog.grantsEvent(
                "persist deferred reason=\(reason.rawValue) memory=\(grants.allGrants().count)"
            )
            refreshGrantRows()
            return
        }

        let disk = Self.readGrantDisk()
        let pairedIDs = Set(pairedAgents.map(\.id))
        let next = GrantPersistPolicy.mergedGrants(
            memory: grants.allGrants(),
            disk: disk.snapshot?.grants ?? [],
            pairedAgentIDs: pairedIDs,
            dropAgentIDs: dropAgentIDs
        )
        let allowsEmpty = reason == .clear || reason == .revokeAgent
        if GrantPersistPolicy.shouldKeepExistingFile(
            diskGrantCount: disk.snapshot?.grants.count,
            diskReadable: disk.missing || disk.snapshot != nil,
            nextGrantCount: next.count,
            allowsEmptyOverwrite: allowsEmpty
        ) {
            MailGentLog.grantsEvent(
                "persist refused reason=\(reason.rawValue) memory=\(grants.allGrants().count) disk=\(disk.snapshot?.grants.count ?? -1) readable=\(disk.snapshot != nil) — kept existing file"
            )
            restorePersistedGrants()
            return
        }

        let previousCount = disk.snapshot?.grants.count
        if let previousCount, next.count < previousCount {
            Self.backupGrantsFile(reason: reason.rawValue)
        }
        let snapshot = GrantSnapshot(grants: next)
        do {
            try FileManager.default.createDirectory(
                at: Self.grantsFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(snapshot).write(to: Self.grantsFileURL, options: .atomic)
            MailGentLog.grantsEvent(
                "persist wrote reason=\(reason.rawValue) count=\(next.count) previous=\(previousCount.map(String.init) ?? "none") \(Self.grantDigest(next))"
            )
        } catch {
            MailGentLog.grantsEvent("persist failed reason=\(reason.rawValue) error=\(error)")
        }
        refreshGrantRows()
    }

    private func restorePersistedRules() {
        guard
            let data = try? Data(contentsOf: Self.rulesFileURL),
            let snapshot = try? JSONDecoder().decode(RuleSnapshot.self, from: data)
        else {
            rules.replace(with: RuleSnapshot())
            ruleRevision &+= 1
            return
        }
        let migrated = RuleStore.migrateLegacySharedEnablements(
            snapshot,
            agentIDs: pairedAgents.map(\.id)
        )
        rules.replace(with: migrated)
        ruleRevision &+= 1
        if migrated != snapshot {
            persistRules()
        }
    }

    private func persistRules() {
        if grantDeskPersistDeferred {
            ruleRevision &+= 1
            return
        }
        let snapshot = rules.snapshot()
        do {
            try FileManager.default.createDirectory(
                at: Self.rulesFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(snapshot).write(to: Self.rulesFileURL, options: .atomic)
        } catch {
            MailGentLog.trace("agent rules persist failed: \(error)")
        }
        ruleRevision &+= 1
    }

    private func clearPersistedRules() {
        try? FileManager.default.removeItem(at: Self.rulesFileURL)
    }

    private func refreshGrantRows() {
        if let agent = selectedAgent {
            grantRows = grants.list(agentID: agent.id)
        } else {
            grantRows = []
        }
        grantRevision += 1
        MailGentLog.grantsEvent(
            "rows selected=\(grantRows.count) total=\(grants.allGrants().count) rev=\(grantRevision)"
        )
    }

    private func clearPersistedGrants(reason: String) {
        let disk = Self.readGrantDisk()
        if (disk.snapshot?.grants.count ?? 0) > 0 || (!disk.missing && disk.snapshot == nil) {
            Self.backupGrantsFile(reason: reason)
        }
        guard !disk.missing else {
            MailGentLog.grantsEvent("file remove skipped reason=\(reason) — already absent")
            return
        }
        do {
            try FileManager.default.removeItem(at: Self.grantsFileURL)
            MailGentLog.grantsEvent(
                "file removed reason=\(reason) previous=\(disk.snapshot?.grants.count ?? -1)"
            )
        } catch {
            MailGentLog.grantsEvent("file remove failed reason=\(reason) error=\(error)")
        }
    }

    private struct GrantDisk {
        var missing: Bool
        var bytes: Int
        var snapshot: GrantSnapshot?
        var error: String?
    }

    private static func readGrantDisk() -> GrantDisk {
        let url = grantsFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return GrantDisk(missing: true, bytes: 0, snapshot: nil, error: nil)
        }
        do {
            let data = try Data(contentsOf: url)
            do {
                let snapshot = try JSONDecoder().decode(GrantSnapshot.self, from: data)
                return GrantDisk(missing: false, bytes: data.count, snapshot: snapshot, error: nil)
            } catch {
                return GrantDisk(missing: false, bytes: data.count, snapshot: nil, error: String(describing: error))
            }
        } catch {
            return GrantDisk(missing: false, bytes: 0, snapshot: nil, error: String(describing: error))
        }
    }

    private static func backupGrantsFile(reason: String) {
        let source = grantsFileURL
        let backup = source.deletingLastPathComponent().appendingPathComponent("grants.json.bak")
        do {
            if FileManager.default.fileExists(atPath: backup.path) {
                try FileManager.default.removeItem(at: backup)
            }
            try FileManager.default.copyItem(at: source, to: backup)
            MailGentLog.grantsEvent("backup wrote \(backup.lastPathComponent) reason=\(reason)")
        } catch {
            MailGentLog.grantsEvent("backup failed reason=\(reason) error=\(error)")
        }
    }

    private static func shortID(_ id: String) -> String {
        String(id.prefix(8))
    }

    /// Agent, account, placement, and mode. No participant addresses.
    private static func grantDigest(_ grants: [Grant]) -> String {
        guard !grants.isEmpty else { return "digest=empty" }
        let grouped = Dictionary(grouping: grants, by: \.agentID)
        let parts = grouped.keys.sorted().map { agentID in
            let rows = grouped[agentID] ?? []
            let sample = rows.prefix(12).map { grant in
                "\(grant.mode.rawValue):\(grant.accountID)/\(grant.placement ?? "*")"
            }.joined(separator: ",")
            let extra = rows.count > 12 ? " +\(rows.count - 12)" : ""
            return "\(shortID(agentID)):\(rows.count)[\(sample)\(extra)]"
        }
        return parts.joined(separator: " ")
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
            rules: rules,
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

    private static var rulesFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MailGent", isDirectory: true)
            .appendingPathComponent("rules.json")
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
    let ruleSnapshot: RuleSnapshot
    let selectedAccessKey: String?
    let leakGuardPolicy: OutboundLeakGuardPolicy
}
