import Foundation

/// User decision on conditional field access prompt (Remember-Ask cache + menu Allow/Block).
public enum ConditionalAccessDecision: String, Sendable, Codable {
    case allow
    case block
}

/// Prompter result for one Ask window. `recheck` re-runs grant→rules→Ask and is never cached.
public enum ConditionalAccessPromptOutcome: String, Sendable, Codable {
    case allow
    case block
    case recheck

    public var decision: ConditionalAccessDecision? {
        switch self {
        case .allow: return .allow
        case .block: return .block
        case .recheck: return nil
        }
    }
}

/// One Ask-field value shown to the human before Allow / Block.
public struct ConditionalFieldPreviewLine: Equatable, Sendable {
    public let label: String
    public let value: String
    /// Optional status chip on the title row (e.g. Body → "HTML only").
    public let badge: String?

    public init(label: String, value: String, badge: String? = nil) {
        self.label = label
        self.value = value
        self.badge = badge
    }
}

/// Envelope lines shown on the Ask prompt (human-only; not agent disclosure).
public struct ConditionalMessageEnvelope: Equatable, Sendable {
    public let subject: String
    public let from: String
    public let to: String
    public let cc: String
    public let date: String

    public init(
        subject: String = "",
        from: String = "",
        to: String = "",
        cc: String = "",
        date: String = ""
    ) {
        self.subject = subject
        self.from = from
        self.to = to
        self.cc = cc
        self.date = date
    }
}

/// Context for an Ask (conditional) prompt on MCP get.
public struct ConditionalAccessPromptContext: Equatable, Sendable {
    public let agentID: String
    public let agentName: String
    public let accountID: String
    public let placement: String
    public let messageID: String
    public let internetMessageID: String
    public let requestedFields: [String]
    /// Values for `requestedFields` only (what Allow would disclose).
    public let fieldPreviews: [ConditionalFieldPreviewLine]
    /// Pretty HTML body for in-app Preview (Companion `MessageBodyView`); nil when absent.
    public let htmlBody: String?
    /// Message envelope for the Ask meta card (always for the human, independent of Ask fields).
    public let envelope: ConditionalMessageEnvelope

    public init(
        agentID: String,
        agentName: String,
        accountID: String,
        placement: String,
        messageID: String,
        internetMessageID: String = "",
        requestedFields: [String],
        fieldPreviews: [ConditionalFieldPreviewLine],
        htmlBody: String? = nil,
        envelope: ConditionalMessageEnvelope = ConditionalMessageEnvelope()
    ) {
        self.agentID = agentID
        self.agentName = agentName
        self.accountID = accountID
        self.placement = placement
        self.messageID = messageID
        self.internetMessageID = internetMessageID
        self.requestedFields = requestedFields
        self.fieldPreviews = fieldPreviews
        self.htmlBody = htmlBody
        self.envelope = envelope
    }

    public var mailURL: URL? {
        AppleMailHandoff.messageURL(internetMessageID: internetMessageID)
    }

    /// Message shape for rule matcher ranking in the Ask rule editor (From/Subject/When).
    public func matcherProbeMessage(body: String = "") -> IndexedMessage {
        IndexedMessage(
            id: messageID,
            accountID: accountID,
            placement: placement,
            from: envelope.from,
            to: envelope.to,
            cc: envelope.cc,
            date: envelope.date,
            subject: envelope.subject,
            body: body,
            isPartial: false
        )
    }
}

/// Process-lifetime Ask decisions for Attachment content (agent + message).
/// Shared across `AgentReadAPI` value copies so gateway rebuilds keep Allow after `get`.
public final class AttachmentContentAskCache: @unchecked Sendable {
    public struct Key: Hashable, Sendable {
        public let agentID: String
        public let accountID: String
        public let placement: String
        public let messageID: String

        public init(agentID: String, accountID: String, placement: String, messageID: String) {
            self.agentID = agentID
            self.accountID = accountID
            self.placement = placement
            self.messageID = messageID
        }
    }

    private let lock = NSLock()
    private var decisions: [Key: ConditionalAccessDecision] = [:]

    public init() {}

    public func decision(for key: Key) -> ConditionalAccessDecision? {
        lock.lock()
        defer { lock.unlock() }
        return decisions[key]
    }

    public func store(_ decision: ConditionalAccessDecision, for key: Key) {
        lock.lock()
        decisions[key] = decision
        lock.unlock()
    }
}

/// Result of `get_attachment`: local temp path when content is granted and available.
public struct AttachmentAccessResult: Equatable, Sendable {
    public enum Access: String, Equatable, Sendable {
        case granted
        case notGranted = "not_granted"
        case notAvailable = "not_available"
        case tooLarge = "too_large"
    }

    public let accountID: String
    public let placement: String
    public let id: String
    public let filename: String
    public let byteCount: Int?
    public let path: String?
    public let isPartial: Bool
    public let attachmentContentAccess: Access
    public let note: String?

    public init(
        accountID: String,
        placement: String,
        id: String,
        filename: String,
        byteCount: Int? = nil,
        path: String? = nil,
        isPartial: Bool,
        attachmentContentAccess: Access,
        note: String? = nil
    ) {
        self.accountID = accountID
        self.placement = placement
        self.id = id
        self.filename = filename
        self.byteCount = byteCount
        self.path = path
        self.isPartial = isPartial
        self.attachmentContentAccess = attachmentContentAccess
        self.note = note
    }
}

/// One Mail account for agents: identity plus grant-filtered placement ids.
/// Empty `placements` only appear when `listAccounts(..., includeEmptyPlacements: true)` —
/// meaning the identity is known but this agent has no read grant.
public struct AgentAccount: Equatable, Sendable {
    public let accountID: String
    public let displayName: String
    public let email: String?
    public let placements: [String]

    public init(accountID: String, displayName: String, email: String?, placements: [String]) {
        self.accountID = accountID
        self.displayName = displayName
        self.email = email
        self.placements = placements
    }
}

/// ReadAPI surface for paired agents. Every call requires proof of possession.
/// Results are deny-filtered through GrantGate (no grants → empty / not_available).
public struct AgentReadAPI {
    /// Hard reject for attachment bytes delivered via temp file.
    public static let attachmentByteLimit = 25 * 1024 * 1024
    public let read: ReadAPI
    public let pairing: Pairing
    public let grants: GrantGate
    public let leakGuard: OutboundLeakGuard
    public let rules: RuleStore
    public let audit: AuditLog?
    public let attachmentContentAskCache: AttachmentContentAskCache
    public let fieldAskDecisionCache: FieldAskDecisionCache
    /// Optional Accounts*.sqlite overrides for identity resolution (tests).
    public let accountsDatabases: [URL]?
    public var allowConditionalAccessPrompts: Bool
    public var askDecisionCachePolicy: AskDecisionCachePolicy
    public var conditionalAccessPrompter: (@Sendable (ConditionalAccessPromptContext) async -> ConditionalAccessPromptOutcome)?

    public init(
        read: ReadAPI,
        pairing: Pairing,
        grants: GrantGate = GrantGate(),
        leakGuard: OutboundLeakGuard = OutboundLeakGuard(),
        rules: RuleStore = RuleStore(),
        audit: AuditLog? = nil,
        attachmentContentAskCache: AttachmentContentAskCache = AttachmentContentAskCache(),
        fieldAskDecisionCache: FieldAskDecisionCache = FieldAskDecisionCache(),
        accountsDatabases: [URL]? = nil,
        allowConditionalAccessPrompts: Bool = false,
        askDecisionCachePolicy: AskDecisionCachePolicy = .disabled,
        conditionalAccessPrompter: (@Sendable (ConditionalAccessPromptContext) async -> ConditionalAccessPromptOutcome)? = nil
    ) {
        self.read = read
        self.pairing = pairing
        self.grants = grants
        self.leakGuard = leakGuard
        self.rules = rules
        self.audit = audit
        self.attachmentContentAskCache = attachmentContentAskCache
        self.fieldAskDecisionCache = fieldAskDecisionCache
        self.accountsDatabases = accountsDatabases
        self.allowConditionalAccessPrompts = allowConditionalAccessPrompts
        self.askDecisionCachePolicy = askDecisionCachePolicy
        self.conditionalAccessPrompter = conditionalAccessPrompter
    }

    @discardableResult
    public func authenticate(_ credential: String?) throws -> PairedAgent {
        try pairing.authenticate(credential: credential)
    }
    
    /// Ask resolution for one get: effective modes plus which Ask fields were prompted / decided.
    private struct ConditionalFieldResolution: Sendable {
        let fields: GrantFields
        /// Ask fields the user Allowed (audit badge + `conditionalAccessFields`).
        let confirmed: GrantFields
        /// Ask fields the user Blocked (audit badge + `conditionalBlockedFields`).
        let blocked: GrantFields
        /// Ask fields that went through a prompt (Allow or Block).
        let prompted: GrantFields
    }

    /// Resolves Ask mode fields for this get.
    /// When allow is off: Ask → denied (classic On/Off behavior; no popup).
    /// When allow is on: prompt for Ask fields; `recheck` re-reads grant→rules and may re-prompt leftovers.
    /// `limitingAskTo` restricts which Ask fields are prompted (e.g. Attachment content only on `get_attachment`).
    private func resolveConditionalFields(
        agentID: String,
        agentName: String,
        message: ReadMessage,
        limitingAskTo: Set<String>? = nil
    ) async -> ConditionalFieldResolution {
        func isAsk(_ mode: FieldAccessMode, label: String) -> Bool {
            mode == .ask && (limitingAskTo?.contains(label) ?? true)
        }
        func denyAsks(_ fields: GrantFields) -> ConditionalFieldResolution {
            ConditionalFieldResolution(
                fields: GrantFields(
                    subjectMode: isAsk(fields.subjectMode, label: "Subject") ? .off : fields.subjectMode,
                    fromMode: isAsk(fields.fromMode, label: "From") ? .off : fields.fromMode,
                    toMode: isAsk(fields.toMode, label: "To") ? .off : fields.toMode,
                    ccMode: isAsk(fields.ccMode, label: "Cc") ? .off : fields.ccMode,
                    dateMode: isAsk(fields.dateMode, label: "Date") ? .off : fields.dateMode,
                    bodyMode: isAsk(fields.bodyMode, label: "Body") ? .off : fields.bodyMode,
                    attachmentMetadataMode: isAsk(fields.attachmentMetadataMode, label: "Attachment names")
                        ? .off : fields.attachmentMetadataMode,
                    attachmentContentMode: isAsk(fields.attachmentContentMode, label: "Attachment content")
                        ? .off : fields.attachmentContentMode
                ),
                confirmed: .none,
                blocked: .none,
                prompted: .none
            )
        }
        let probe = IndexedMessage(
            id: message.id,
            accountID: message.accountID,
            placement: message.placement,
            from: message.from,
            to: message.to,
            cc: message.cc,
            date: message.date,
            subject: message.subject,
            body: "",
            isPartial: message.isPartial
        )
        let policy = askDecisionCachePolicy

        while true {
            guard let fields = effectiveFields(for: probe, agentID: agentID) else {
                return ConditionalFieldResolution(
                    fields: .none,
                    confirmed: .none,
                    blocked: .none,
                    prompted: .none
                )
            }
            if !allowConditionalAccessPrompts {
                // Feature off → Ask denied (same as classic grants without conditional).
                return denyAsks(fields)
            }

            let askMask = Self.askMask(fields, limitingAskTo: limitingAskTo)
            let askLabels = collectAskFields(fields).filter { limitingAskTo?.contains($0) ?? true }
            guard !askLabels.isEmpty else {
                return ConditionalFieldResolution(
                    fields: fields,
                    confirmed: .none,
                    blocked: .none,
                    prompted: .none
                )
            }

            var cachedAllow: Set<String> = []
            var cachedBlock: Set<String> = []
            var needPrompt: [String] = []
            for label in askLabels {
                if let cached = fieldAskDecisionCache.decision(
                    agentID: agentID,
                    accountID: message.accountID,
                    placement: message.placement,
                    messageID: message.id,
                    field: label,
                    policy: policy
                ) {
                    if cached == .allow {
                        cachedAllow.insert(label)
                    } else {
                        cachedBlock.insert(label)
                    }
                } else {
                    needPrompt.append(label)
                }
            }

            if needPrompt.isEmpty {
                let allowLabels = cachedAllow
                let blockLabels = cachedBlock
                return ConditionalFieldResolution(
                    fields: Self.applyingAskDecisions(
                        fields,
                        allowLabels: allowLabels,
                        blockLabels: blockLabels,
                        limitingAskTo: limitingAskTo
                    ),
                    confirmed: Self.mask(forLabels: allowLabels, in: askMask),
                    blocked: Self.mask(forLabels: blockLabels, in: askMask),
                    prompted: .none
                )
            }

            guard let prompter = conditionalAccessPrompter else {
                // No prompter → allow remaining Ask fields (fallback; not user-confirmed).
                let allowLabels = cachedAllow.union(needPrompt)
                return ConditionalFieldResolution(
                    fields: Self.applyingAskDecisions(
                        fields,
                        allowLabels: allowLabels,
                        blockLabels: cachedBlock,
                        limitingAskTo: limitingAskTo
                    ),
                    confirmed: Self.mask(forLabels: allowLabels, in: askMask),
                    blocked: Self.mask(forLabels: cachedBlock, in: askMask),
                    prompted: Self.mask(forLabels: Set(needPrompt), in: askMask)
                )
            }

            let context = ConditionalAccessPromptContext(
                agentID: agentID,
                agentName: agentName,
                accountID: message.accountID,
                placement: message.placement,
                messageID: message.id,
                internetMessageID: message.internetMessageID,
                requestedFields: needPrompt,
                fieldPreviews: Self.fieldPreviews(message: message, askLabels: needPrompt),
                // Raw HTML for Ask message preview (not prettyHTMLBody — prefix heuristic can nil it).
                htmlBody: message.htmlBody,
                envelope: ConditionalMessageEnvelope(
                    subject: message.subject,
                    from: message.from,
                    to: message.to,
                    cc: message.cc,
                    date: message.date
                )
            )
            let outcome = await prompter(context)
            switch outcome {
            case .recheck:
                continue
            case .allow, .block:
                guard let decision = outcome.decision else { continue }
                if policy.enabled {
                    for label in needPrompt {
                        fieldAskDecisionCache.store(
                            decision,
                            agentID: agentID,
                            accountID: message.accountID,
                            placement: message.placement,
                            messageID: message.id,
                            field: label,
                            policy: policy
                        )
                    }
                }
                let promptedAllow: Set<String> = decision == .allow ? Set(needPrompt) : []
                let promptedBlock: Set<String> = decision == .block ? Set(needPrompt) : []
                let allowLabels = cachedAllow.union(promptedAllow)
                let blockLabels = cachedBlock.union(promptedBlock)
                let promptedLabels = promptedAllow.union(promptedBlock)
                return ConditionalFieldResolution(
                    fields: Self.applyingAskDecisions(
                        fields,
                        allowLabels: allowLabels,
                        blockLabels: blockLabels,
                        limitingAskTo: limitingAskTo
                    ),
                    confirmed: Self.mask(forLabels: allowLabels, in: askMask),
                    blocked: Self.mask(forLabels: blockLabels, in: askMask),
                    prompted: Self.mask(forLabels: promptedLabels, in: askMask)
                )
            }
        }
    }

    private static func applyingAskDecisions(
        _ fields: GrantFields,
        allowLabels: Set<String>,
        blockLabels: Set<String>,
        limitingAskTo: Set<String>?
    ) -> GrantFields {
        func resolve(_ mode: FieldAccessMode, label: String) -> FieldAccessMode {
            guard mode == .ask, limitingAskTo?.contains(label) ?? true else { return mode }
            if allowLabels.contains(label) { return .on }
            if blockLabels.contains(label) { return .off }
            return .off
        }
        return GrantFields(
            subjectMode: resolve(fields.subjectMode, label: "Subject"),
            fromMode: resolve(fields.fromMode, label: "From"),
            toMode: resolve(fields.toMode, label: "To"),
            ccMode: resolve(fields.ccMode, label: "Cc"),
            dateMode: resolve(fields.dateMode, label: "Date"),
            bodyMode: resolve(fields.bodyMode, label: "Body"),
            attachmentMetadataMode: resolve(fields.attachmentMetadataMode, label: "Attachment names"),
            attachmentContentMode: resolve(fields.attachmentContentMode, label: "Attachment content")
        )
    }

    private static func mask(forLabels labels: Set<String>, in askMask: GrantFields) -> GrantFields {
        // Set content after init — GrantFields init clears content when metadata is off,
        // but content-only Ask (names already On on Scope) must still count as confirmed.
        var mask = GrantFields(
            subjectMode: labels.contains("Subject") && askMask.subject ? .on : .off,
            fromMode: labels.contains("From") && askMask.from ? .on : .off,
            toMode: labels.contains("To") && askMask.to ? .on : .off,
            ccMode: labels.contains("Cc") && askMask.cc ? .on : .off,
            dateMode: labels.contains("Date") && askMask.date ? .on : .off,
            bodyMode: labels.contains("Body") && askMask.body ? .on : .off,
            attachmentMetadataMode: labels.contains("Attachment names") && askMask.attachmentMetadata
                ? .on : .off,
            attachmentContentMode: .off
        )
        if labels.contains("Attachment content"), askMask.attachmentContent {
            mask.attachmentContentMode = .on
        }
        return mask
    }

    private static let bodyPreviewCap = 2_000

    private static func fieldPreviews(
        message: ReadMessage,
        askLabels: [String]
    ) -> [ConditionalFieldPreviewLine] {
        askLabels.map { label in
            let value = previewValue(for: label, message: message)
            let badge: String? =
                label == "Body" && Self.isHTMLOnlyBody(message) ? "HTML only" : nil
            return ConditionalFieldPreviewLine(label: label, value: value, badge: badge)
        }
    }

    private static func previewValue(for label: String, message: ReadMessage) -> String {
        let raw: String
        switch label {
        case "Subject":
            raw = message.subject
        case "From":
            raw = message.from
        case "To":
            raw = message.to
        case "Cc":
            raw = message.cc
        case "Date":
            raw = message.date
        case "Body":
            // Prefer HTML → plain so HTML-only mail (indexed body empty → `.notAvailable`)
            // still fills the Ask left-pane Body card. Matches right-pane `htmlBody` preview.
            if let html = message.htmlBody,
               !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                raw = MailMIME.plainText(fromHTML: html)
            } else {
                switch message.body {
                case .text(let text):
                    if text.contains("<") || text.contains("body {") || text.contains("&zwnj;") {
                        raw = MailMIME.plainText(fromHTML: text)
                    } else {
                        raw = MailMIME.decodeHTMLEntities(text)
                    }
                case .notAvailable, .notGranted:
                    raw = ""
                }
            }
        case "Attachment names", "Attachment content":
            if message.attachments.isEmpty {
                raw = ""
            } else {
                raw = message.attachments.map(\.filename).joined(separator: ", ")
            }
        default:
            raw = ""
        }
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if label == "Body" {
            trimmed = MailMIME.stripLeadingByteCountPrefix(trimmed)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else {
            return "(empty)"
        }
        if label == "Body", trimmed.count > bodyPreviewCap {
            trimmed = String(trimmed.prefix(bodyPreviewCap)) + "…"
        }
        return trimmed
    }

    /// True when there is HTML but no plain-text body part (common marketing mail).
    private static func isHTMLOnlyBody(_ message: ReadMessage) -> Bool {
        guard let html = message.htmlBody,
              !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }
        switch message.body {
        case .text(let text):
            return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .notAvailable:
            return true
        case .notGranted:
            return false
        }
    }

    /// Modes that are Ask, expressed as `.on` bits for mask/union helpers.
    /// Sets `attachmentContentMode` after init so content-only Ask is not cleared when names are On (not Ask).
    private static func askMask(_ fields: GrantFields, limitingAskTo: Set<String>? = nil) -> GrantFields {
        func included(_ mode: FieldAccessMode, label: String) -> Bool {
            mode == .ask && (limitingAskTo?.contains(label) ?? true)
        }
        var mask = GrantFields(
            subjectMode: included(fields.subjectMode, label: "Subject") ? .on : .off,
            fromMode: included(fields.fromMode, label: "From") ? .on : .off,
            toMode: included(fields.toMode, label: "To") ? .on : .off,
            ccMode: included(fields.ccMode, label: "Cc") ? .on : .off,
            dateMode: included(fields.dateMode, label: "Date") ? .on : .off,
            bodyMode: included(fields.bodyMode, label: "Body") ? .on : .off,
            attachmentMetadataMode: included(fields.attachmentMetadataMode, label: "Attachment names")
                ? .on : .off,
            attachmentContentMode: .off
        )
        if included(fields.attachmentContentMode, label: "Attachment content") {
            mask.attachmentContentMode = .on
        }
        return mask
    }

    private func rememberAttachmentContentAsk(
        agentID: String,
        message: ReadMessage,
        resolution: ConditionalFieldResolution
    ) {
        guard resolution.prompted.attachmentContent else { return }
        let key = AttachmentContentAskCache.Key(
            agentID: agentID,
            accountID: message.accountID,
            placement: message.placement,
            messageID: message.id
        )
        attachmentContentAskCache.store(
            resolution.confirmed.attachmentContent ? .allow : .block,
            for: key
        )
    }

    /// Effective Attachment content bit after cache / content-only Ask (Off/On unchanged).
    private func resolveAttachmentContentAllowed(
        fields: GrantFields,
        agentID: String,
        agentName: String,
        message: ReadMessage
    ) async -> (allowed: Bool, askBlocked: Bool) {
        switch fields.attachmentContentMode {
        case .on:
            return (true, false)
        case .off:
            return (false, false)
        case .ask:
            let key = AttachmentContentAskCache.Key(
                agentID: agentID,
                accountID: message.accountID,
                placement: message.placement,
                messageID: message.id
            )
            if let cached = attachmentContentAskCache.decision(for: key) {
                return (cached == .allow, cached == .block)
            }
            let resolution = await resolveConditionalFields(
                agentID: agentID,
                agentName: agentName,
                message: message,
                limitingAskTo: ["Attachment content"]
            )
            rememberAttachmentContentAsk(agentID: agentID, message: message, resolution: resolution)
            return (resolution.fields.attachmentContent, resolution.blocked.attachmentContent)
        }
    }

    private func collectAskFields(_ fields: GrantFields) -> [String] {
        var result: [String] = []
        if fields.subjectMode == .ask { result.append("Subject") }
        if fields.fromMode == .ask { result.append("From") }
        if fields.toMode == .ask { result.append("To") }
        if fields.ccMode == .ask { result.append("Cc") }
        if fields.dateMode == .ask { result.append("Date") }
        if fields.bodyMode == .ask { result.append("Body") }
        if fields.attachmentMetadataMode == .ask { result.append("Attachment names") }
        if fields.attachmentContentMode == .ask { result.append("Attachment content") }
        return result
    }

    private static func conditionalFieldLabels(_ confirmed: GrantFields) -> [String] {
        var result: [String] = []
        if confirmed.subject { result.append("Subject") }
        if confirmed.from { result.append("From") }
        if confirmed.to { result.append("To") }
        if confirmed.cc { result.append("Cc") }
        if confirmed.date { result.append("Date") }
        if confirmed.body { result.append("Body") }
        if confirmed.attachmentMetadata { result.append("Attachment names") }
        if confirmed.attachmentContent { result.append("Attachment content") }
        return result
    }

    public func list(
        credential: String?,
        limit: Int = 25,
        cursor: String? = nil,
        accountID: String? = nil,
        placement: String? = nil
    ) throws -> Page<IndexedMessage> {
        let started = Date()
        let agent = try authenticate(credential)
        let request = AuditJSON.request([
            "limit": limit,
            "cursor": cursor,
            "accountID": accountID,
            "placement": placement
        ])
        do {
            let page = try read.list(
                limit: limit,
                cursor: cursor,
                accountID: accountID,
                placement: placement
            )
            let filtered = filterPage(page, agentID: agent.id, limit: limit)
            record(
                kind: .list,
                agent: agent,
                started: started,
                detail: "list",
                requestSummary: request,
                responseSummary: AuditJSON.json(AuditJSON.page(filtered)),
                messages: messageRefs(filtered.items, agentID: agent.id)
            )
            return filtered
        } catch {
            record(
                kind: .list,
                agent: agent,
                started: started,
                detail: "list",
                requestSummary: request,
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    public func listNew(
        credential: String?,
        limit: Int = 100,
        cursor: String? = nil
    ) throws -> Page<IndexedMessage> {
        let started = Date()
        let agent = try authenticate(credential)
        let request = AuditJSON.request([
            "limit": limit,
            "cursor": cursor
        ])
        do {
            let page = try read.listNew(limit: limit, cursor: cursor)
            let filtered = filterPage(page, agentID: agent.id, limit: limit)
            record(
                kind: .listNew,
                agent: agent,
                started: started,
                detail: "list_new",
                requestSummary: request,
                responseSummary: AuditJSON.json(AuditJSON.page(filtered)),
                messages: messageRefs(filtered.items, agentID: agent.id)
            )
            return filtered
        } catch {
            record(
                kind: .listNew,
                agent: agent,
                started: started,
                detail: "list_new",
                requestSummary: request,
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    public func search(
        _ query: String,
        credential: String?,
        limit: Int = 25,
        cursor: String? = nil,
        accountID: String? = nil,
        placement: String? = nil
    ) throws -> Page<IndexedMessage> {
        let started = Date()
        let agent = try authenticate(credential)
        let request = AuditJSON.request([
            "query": query,
            "limit": limit,
            "cursor": cursor,
            "accountID": accountID,
            "placement": placement
        ])
        do {
            // Over-fetch then deny-filter so counts/pages never include denied rows.
            let page = try read.search(
                query,
                limit: 100,
                cursor: cursor,
                accountID: accountID,
                placement: placement
            )
            let filtered = filterPage(page, agentID: agent.id, limit: limit)
            record(
                kind: .search,
                agent: agent,
                started: started,
                detail: query,
                requestSummary: request,
                responseSummary: AuditJSON.json(AuditJSON.page(filtered)),
                messages: messageRefs(filtered.items, agentID: agent.id)
            )
            return filtered
        } catch {
            record(
                kind: .search,
                agent: agent,
                started: started,
                detail: query,
                requestSummary: request,
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    public func get(
        credential: String?,
        accountID: String,
        placement: String,
        id: String
    ) async throws -> ReadMessage {
        let started = Date()
        let agent = try authenticate(credential)
        let path = "\(accountID)/\(placement)/\(id)"
        let request = AuditJSON.request([
            "accountID": accountID,
            "placement": placement,
            "id": id
        ])
        do {
            let message = try read.get(accountID: accountID, placement: placement, id: id)
            let probe = IndexedMessage(
                id: message.id,
                accountID: message.accountID,
                placement: message.placement,
                from: message.from,
                to: message.to,
                cc: message.cc,
                date: message.date,
                subject: message.subject,
                body: "",
                isPartial: message.isPartial
            )
            guard effectiveGrant(for: probe, agentID: agent.id) != nil else {
                record(
                    kind: .get,
                    agent: agent,
                    started: started,
                    detail: path,
                    requestSummary: request,
                    outcome: .error("unauthorized")
                )
                throw PairingError.unauthorized
            }
            let resolution = await resolveConditionalFields(
                agentID: agent.id,
                agentName: agent.name,
                message: message
            )
            rememberAttachmentContentAsk(
                agentID: agent.id,
                message: message,
                resolution: resolution
            )
            // Refresh overlays after possible mid-Ask rule rematch.
            let appliedRules = effectiveGrant(for: probe, agentID: agent.id)?.applied ?? []
            let fields = resolution.fields
            let granted = message.applying(fields)
            var (sanitized, subjectField, bodyField) = sanitizeGet(granted, fields: fields)
            // Prompted and cache-reuse both count as conditional (cache is silent — no second dialog).
            if resolution.confirmed.subject || resolution.blocked.subject {
                subjectField = subjectField.markingConditionalPrompt(
                    allowed: resolution.confirmed.subject
                )
            }
            if resolution.confirmed.body || resolution.blocked.body {
                bodyField = bodyField.markingConditionalPrompt(
                    allowed: resolution.confirmed.body
                )
            }
            let conditionalLabels = Self.conditionalFieldLabels(resolution.confirmed)
            let blockedLabels = Self.conditionalFieldLabels(resolution.blocked)
            let cachedFields = resolution.confirmed
                .unioning(resolution.blocked)
                .bitsNotIn(resolution.prompted)
            let access = ReadMessageAccess(
                subject: subjectField,
                body: bodyField,
                conditionalAccessFields: conditionalLabels,
                conditionalBlockedFields: blockedLabels
            )
            let agentMessage = sanitized.withLeakGuardAccess(access)
            record(
                kind: .get,
                agent: agent,
                started: started,
                detail: path,
                requestSummary: request,
                responseSummary: AuditJSON.json(AuditJSON.messageDetail(agentMessage)),
                messages: [
                    AuditMessageRef(
                        agentMessage,
                        fields: fields,
                        subjectSanitized: subjectField,
                        bodySanitized: bodyField,
                        appliedRules: appliedRules,
                        conditionalFields: resolution.confirmed,
                        conditionalBlockedFields: resolution.blocked,
                        conditionalCachedFields: cachedFields
                    )
                ]
            )
            return agentMessage
        } catch let error as PairingError where error == .unauthorized {
            throw error
        } catch {
            record(
                kind: .get,
                agent: agent,
                started: started,
                detail: path,
                requestSummary: request,
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    public func getAttachment(
        credential: String?,
        accountID: String,
        placement: String,
        id: String,
        filename: String
    ) async throws -> AttachmentAccessResult {
        let started = Date()
        let agent = try authenticate(credential)
        let path = "\(accountID)/\(placement)/\(id)"
        let request = AuditJSON.request([
            "accountID": accountID,
            "placement": placement,
            "id": id,
            "filename": filename
        ])
        do {
            let message = try read.get(accountID: accountID, placement: placement, id: id)
            let probe = IndexedMessage(
                id: message.id,
                accountID: message.accountID,
                placement: message.placement,
                from: message.from,
                to: message.to,
                cc: message.cc,
                date: message.date,
                subject: message.subject,
                body: "",
                isPartial: message.isPartial
            )
            guard let grant = effectiveGrant(for: probe, agentID: agent.id) else {
                record(
                    kind: .getAttachment,
                    agent: agent,
                    started: started,
                    detail: path,
                    requestSummary: request,
                    outcome: .error("unauthorized")
                )
                throw PairingError.unauthorized
            }
            let fields = grant.fields

            // Resolve the actual attachment metadata first. A non-existent filename is
            // notAvailable regardless of grant/Ask state, and we must not prompt the user
            // for an attachment that isn't there.
            guard let meta = message.attachments.first(where: {
                $0.filename.lowercased() == filename.lowercased()
            }) else {
                let note: String
                if message.attachments.isEmpty {
                    note = message.isPartial
                        ? "Attachment not available. Message is partial; Apple Mail may not have downloaded this part."
                        : "Attachment not available for this message."
                } else {
                    note = "No attachment named \"\(filename)\" on this message."
                }
                let result = AttachmentAccessResult(
                    accountID: accountID,
                    placement: placement,
                    id: id,
                    filename: filename,
                    isPartial: message.isPartial,
                    attachmentContentAccess: .notAvailable,
                    note: note
                )

                let auditAttachments: [MailAttachment] = message.attachments.filter {
                    $0.filename.lowercased() == filename.lowercased()
                }

                record(
                    kind: .getAttachment,
                    agent: agent,
                    started: started,
                    detail: "\(path)/\(result.filename)",
                    requestSummary: request,
                    responseSummary: AuditJSON.json(
                        AuditJSON.attachmentResult(result, pathForAudit: true)
                    ),
                    messages: [
                        AuditMessageRef(
                            accountID: message.accountID,
                            placement: message.placement,
                            id: message.id,
                            subject: fields.subject ? message.subject : "",
                            from: fields.from ? message.from : "",
                            date: fields.date ? message.date : "",
                            to: fields.to ? message.to : "",
                            cc: fields.cc ? message.cc : "",
                            bodyAccess: fields.body ? .notAvailable : .notGranted,
                            fields: fields,
                            attachments: auditAttachments,
                            appliedRules: grant.applied
                        )
                    ]
                )
                return result
            }

            let contentAccess = await resolveAttachmentContentAllowed(
                fields: fields,
                agentID: agent.id,
                agentName: agent.name,
                message: message
            )

            let result: AttachmentAccessResult
            if !contentAccess.allowed {
                let note: String
                if contentAccess.askBlocked {
                    note = "Attachment content omitted: the user blocked Attachment Content on Ask for this message."
                } else {
                    note = "Attachment content omitted: the active grant does not allow attachment content. Ask the user to enable Attachment Content on the grant."
                }
                result = AttachmentAccessResult(
                    accountID: accountID,
                    placement: placement,
                    id: id,
                    filename: meta.filename,
                    byteCount: meta.byteCount,
                    isPartial: message.isPartial,
                    attachmentContentAccess: .notGranted,
                    note: note
                )
            } else if meta.byteCount > Self.attachmentByteLimit {
                result = AttachmentAccessResult(
                    accountID: accountID,
                    placement: placement,
                    id: id,
                    filename: meta.filename,
                    byteCount: meta.byteCount,
                    isPartial: message.isPartial,
                    attachmentContentAccess: .tooLarge,
                    note: "Attachment exceeds the \(Self.attachmentByteLimit)-byte size limit."
                )
            } else {
                result = try loadAttachmentResult(
                    accountID: accountID,
                    placement: placement,
                    id: id,
                    filename: meta.filename,
                    knownByteCount: meta.byteCount,
                    isPartial: message.isPartial
                )
            }

            let auditAttachments: [MailAttachment]
            if let byteCount = result.byteCount {
                auditAttachments = [MailAttachment(filename: result.filename, byteCount: byteCount)]
            } else if result.attachmentContentAccess != .notAvailable {
                auditAttachments = [MailAttachment(filename: result.filename, byteCount: 0)]
            } else {
                auditAttachments = message.attachments.filter {
                    $0.filename.lowercased() == filename.lowercased()
                }
            }

            record(
                kind: .getAttachment,
                agent: agent,
                started: started,
                detail: "\(path)/\(result.filename)",
                requestSummary: request,
                responseSummary: AuditJSON.json(
                    AuditJSON.attachmentResult(result, pathForAudit: true)
                ),
                messages: [
                    AuditMessageRef(
                        accountID: message.accountID,
                        placement: message.placement,
                        id: message.id,
                        subject: fields.subject ? message.subject : "",
                        from: fields.from ? message.from : "",
                        date: fields.date ? message.date : "",
                        to: fields.to ? message.to : "",
                        cc: fields.cc ? message.cc : "",
                        bodyAccess: fields.body ? .notAvailable : .notGranted,
                        fields: fields,
                        attachments: auditAttachments,
                        appliedRules: grant.applied
                    )
                ]
            )
            return result
        } catch let error as PairingError where error == .unauthorized {
            throw error
        } catch {
            record(
                kind: .getAttachment,
                agent: agent,
                started: started,
                detail: path,
                requestSummary: request,
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    /// Lists Mail identities with grant-filtered placements.
    /// - Parameter includeEmptyPlacements: When `false` (default), omit accounts with no
    ///   granted placements. When `true`, include those identities with `placements: []`.
    public func listAccounts(
        credential: String?,
        includeEmptyPlacements: Bool = false
    ) throws -> [AgentAccount] {
        let started = Date()
        let agent = try authenticate(credential)
        do {
            let identities = try MailAccountIdentityResolver.resolve(
                in: read.index.store,
                accountsDatabases: accountsDatabases
            )
            let granted = grants.filter(try read.listPlacements(), agentID: agent.id)
            var placementsByAccount: [String: [String]] = [:]
            for placement in granted {
                placementsByAccount[placement.accountID, default: []].append(placement.id)
            }
            var accounts = identities.map { identity in
                AgentAccount(
                    accountID: identity.id,
                    displayName: identity.displayName,
                    email: identity.email,
                    placements: (placementsByAccount[identity.id] ?? []).sorted {
                        $0.localizedStandardCompare($1) == .orderedAscending
                    }
                )
            }
            if !includeEmptyPlacements {
                accounts = accounts.filter { !$0.placements.isEmpty }
            }
            let flatPlacements = granted.map {
                AuditPlacementRef(accountID: $0.accountID, placement: $0.id)
            }
            record(
                kind: .listAccounts,
                agent: agent,
                started: started,
                detail: "list_accounts",
                requestSummary: AuditJSON.json([:] as [String: Any]),
                responseSummary: AuditJSON.json(AuditJSON.accounts(accounts)),
                placements: flatPlacements
            )
            return accounts
        } catch {
            record(
                kind: .listAccounts,
                agent: agent,
                started: started,
                detail: "list_accounts",
                requestSummary: AuditJSON.json([:] as [String: Any]),
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    public func freshness(credential: String?) throws -> IndexFreshness {
        let started = Date()
        let agent = try authenticate(credential)
        do {
            let freshness = try read.freshness()
            record(
                kind: .status,
                agent: agent,
                started: started,
                detail: "status",
                requestSummary: AuditJSON.json([:] as [String: Any]),
                responseSummary: AuditJSON.json(AuditJSON.freshness(freshness))
            )
            return freshness
        } catch {
            record(
                kind: .status,
                agent: agent,
                started: started,
                detail: "status",
                requestSummary: AuditJSON.json([:] as [String: Any]),
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    public func updateIndex(credential: String?, updater: any IndexUpdating) async throws -> IndexUpdateOutcome {
        let started = Date()
        let agent = try authenticate(credential)
        do {
            let outcome = try await updater.update()
            record(
                kind: .updateIndex,
                agent: agent,
                started: started,
                detail: "new=\(outcome.newCount) removed=\(outcome.removedCount)",
                requestSummary: AuditJSON.json([:] as [String: Any]),
                responseSummary: AuditJSON.json(AuditJSON.update(outcome))
            )
            return outcome
        } catch {
            record(
                kind: .updateIndex,
                agent: agent,
                started: started,
                detail: "update",
                requestSummary: AuditJSON.json([:] as [String: Any]),
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    private func loadAttachmentResult(
        accountID: String,
        placement: String,
        id: String,
        filename: String,
        knownByteCount: Int,
        isPartial: Bool
    ) throws -> AttachmentAccessResult {
        let data: Data
        do {
            data = try read.attachmentData(
                accountID: accountID,
                placement: placement,
                id: id,
                filename: filename
            )
        } catch MailStoreError.attachmentNotFound, MailStoreError.unreadable {
            return AttachmentAccessResult(
                accountID: accountID,
                placement: placement,
                id: id,
                filename: filename,
                byteCount: knownByteCount,
                isPartial: isPartial,
                attachmentContentAccess: .notAvailable,
                note: isPartial
                    ? "Attachment bytes are not on disk. Message is partial; Apple Mail may not have downloaded this part."
                    : "Attachment bytes are not available on disk."
            )
        }
        if data.count > Self.attachmentByteLimit {
            return AttachmentAccessResult(
                accountID: accountID,
                placement: placement,
                id: id,
                filename: filename,
                byteCount: data.count,
                isPartial: isPartial,
                attachmentContentAccess: .tooLarge,
                note: "Attachment exceeds the \(Self.attachmentByteLimit)-byte size limit."
            )
        }
        let fileURL = try Self.writeAttachmentTempFile(filename: filename, data: data)
        return AttachmentAccessResult(
            accountID: accountID,
            placement: placement,
            id: id,
            filename: filename,
            byteCount: data.count,
            path: fileURL.path,
            isPartial: isPartial,
            attachmentContentAccess: .granted
        )
    }

    private static func writeAttachmentTempFile(filename: String, data: Data) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-agent-attachments", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let dest = root.appendingPathComponent(safeAttachmentFilename(filename))
        try data.write(to: dest, options: .atomic)
        return dest
    }

    private static func safeAttachmentFilename(_ filename: String) -> String {
        let base = (filename as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = base
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\0", with: "_")
        return cleaned.isEmpty ? "attachment" : cleaned
    }

    private func filterPage(
        _ page: Page<IndexedMessage>,
        agentID: String,
        limit: Int
    ) -> Page<IndexedMessage> {
        let clamped = min(max(limit, 1), 100)
        let allowed = grants.filter(page.items, agentID: agentID)
        let items = Array(allowed.prefix(clamped)).map { sanitizeListItem($0, agentID: agentID) }
        // Cursor semantics under filtering are approximate for first ship; denied rows
        // never appear and never inflate the returned page.
        let next = allowed.count > clamped ? page.nextCursor : nil
        return Page(items: items, nextCursor: next)
    }

    private func sanitizeListItem(_ item: IndexedMessage, agentID: String) -> IndexedMessage {
        guard let fields = effectiveFields(for: item, agentID: agentID) else { return item }
        let subjectField = leakGuard.sanitize(
            text: item.subject,
            field: .subject,
            accountID: item.accountID,
            placement: item.placement,
            fieldGranted: fields.subject
        )
        guard subjectField.text != item.subject else { return item }
        return IndexedMessage(
            id: item.id,
            accountID: item.accountID,
            placement: item.placement,
            from: item.from,
            to: item.to,
            cc: item.cc,
            date: item.date,
            subject: subjectField.text,
            body: item.body,
            isPartial: item.isPartial
        )
    }

    private func sanitizeGet(
        _ message: ReadMessage,
        fields: GrantFields
    ) -> (ReadMessage, SanitizedField, SanitizedField) {
        let subjectField = leakGuard.sanitize(
            text: message.subject,
            field: .subject,
            accountID: message.accountID,
            placement: message.placement,
            fieldGranted: fields.subject
        )
        var current = message.withSanitizedSubject(subjectField.text)

        let bodyPlain = Self.plainBodyText(from: message)
        let bodyField = leakGuard.sanitize(
            text: bodyPlain,
            field: .body,
            accountID: message.accountID,
            placement: message.placement,
            fieldGranted: fields.body
        )
        let sanitizedBody = Self.readBody(from: bodyField, fields: fields, fallback: message.body)
        current = current.withSanitizedBody(sanitizedBody)
        return (current, subjectField, bodyField)
    }

    private static func plainBodyText(from message: ReadMessage) -> String {
        switch message.body {
        case .text(let text):
            return text
        case .notAvailable:
            if let html = message.prettyHTMLBody,
               !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return MailMIME.plainText(fromHTML: html)
            }
            return ""
        case .notGranted:
            return ""
        }
    }

    private static func readBody(
        from field: SanitizedField,
        fields: GrantFields,
        fallback: ReadBody
    ) -> ReadBody {
        guard fields.body else { return .notGranted }
        switch field.agentAccess {
        case .notGranted:
            return .notGranted
        case .withheldConfidential:
            return .text("")
        case .granted, .sanitized:
            return field.text.isEmpty ? .notAvailable : .text(field.text)
        }
    }

    private func subjectField(for item: IndexedMessage, fields: GrantFields) -> SanitizedField {
        leakGuard.sanitize(
            text: item.subject,
            field: .subject,
            accountID: item.accountID,
            placement: item.placement,
            fieldGranted: fields.subject
        )
    }

    /// Scope base fields, then Pass/Block overlays. nil → message not Scope-allowed (rules never open the gate).
    private func effectiveFields(for message: IndexedMessage, agentID: String) -> GrantFields? {
        effectiveGrant(for: message, agentID: agentID)?.fields
    }

    /// Effective fields plus effectful applied rules for audit.
    private func effectiveGrant(
        for message: IndexedMessage,
        agentID: String
    ) -> (fields: GrantFields, applied: [AppliedGrantRule])? {
        guard let base = grants.effectiveFields(for: message, agentID: agentID) else { return nil }
        return RuleEngine.applyOverlaysWithApplied(
            base: base,
            message: message,
            agentID: agentID,
            rules: rules.allRules(),
            enablements: rules.allEnablements()
        )
    }

    private func record(
        kind: AuditKind,
        agent: PairedAgent,
        started: Date,
        detail: String = "",
        requestSummary: String = "",
        responseSummary: String = "",
        messages: [AuditMessageRef] = [],
        placements: [AuditPlacementRef] = [],
        outcome: AuditOutcome = .ok
    ) {
        audit?.append(
            AuditEntry(
                kind: kind,
                agentID: agent.id,
                agentName: agent.name,
                detail: detail,
                at: started,
                finishedAt: Date(),
                requestSummary: requestSummary,
                responseSummary: responseSummary,
                messages: messages,
                placements: placements,
                outcome: outcome
            )
        )
    }

    private func messageRefs(_ items: [IndexedMessage], agentID: String) -> [AuditMessageRef] {
        items.prefix(AuditLog.messageRefCap).map { item in
            let grant = effectiveGrant(for: item, agentID: agentID)
            let fields = grant?.fields ?? .headersOnly
            let subjectSanitized = subjectField(for: item, fields: fields)
            return AuditMessageRef(
                item,
                fields: fields,
                subjectSanitized: subjectSanitized,
                appliedRules: grant?.applied
            )
        }
    }
}
