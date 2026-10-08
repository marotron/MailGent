import Foundation

/// User decision on conditional field access prompt.
public enum ConditionalAccessDecision: Sendable {
    case allow
    case block
}

/// One Ask-field value shown to the human before Allow / Block.
public struct ConditionalFieldPreviewLine: Equatable, Sendable {
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
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
    public var allowConditionalAccessPrompts: Bool
    public var conditionalAccessPrompter: (@Sendable (ConditionalAccessPromptContext) async -> ConditionalAccessDecision)?

    public init(
        read: ReadAPI,
        pairing: Pairing,
        grants: GrantGate = GrantGate(),
        leakGuard: OutboundLeakGuard = OutboundLeakGuard(),
        rules: RuleStore = RuleStore(),
        audit: AuditLog? = nil,
        allowConditionalAccessPrompts: Bool = false,
        conditionalAccessPrompter: (@Sendable (ConditionalAccessPromptContext) async -> ConditionalAccessDecision)? = nil
    ) {
        self.read = read
        self.pairing = pairing
        self.grants = grants
        self.leakGuard = leakGuard
        self.rules = rules
        self.audit = audit
        self.allowConditionalAccessPrompts = allowConditionalAccessPrompts
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
    /// When allow is on: prompt once for all Ask fields; timeout/dismiss → deny.
    private func resolveConditionalFields(
        _ fields: GrantFields,
        agentName: String,
        message: ReadMessage
    ) async -> ConditionalFieldResolution {
        let askMask = Self.askMask(fields)
        if !allowConditionalAccessPrompts {
            // Feature off → Ask denied (same as classic grants without conditional).
            return ConditionalFieldResolution(
                fields: GrantFields(
                    subjectMode: fields.subjectMode == .ask ? .off : fields.subjectMode,
                    fromMode: fields.fromMode == .ask ? .off : fields.fromMode,
                    toMode: fields.toMode == .ask ? .off : fields.toMode,
                    ccMode: fields.ccMode == .ask ? .off : fields.ccMode,
                    dateMode: fields.dateMode == .ask ? .off : fields.dateMode,
                    bodyMode: fields.bodyMode == .ask ? .off : fields.bodyMode,
                    attachmentMetadataMode: fields.attachmentMetadataMode == .ask
                        ? .off : fields.attachmentMetadataMode,
                    attachmentContentMode: fields.attachmentContentMode == .ask
                        ? .off : fields.attachmentContentMode
                ),
                confirmed: .none,
                blocked: .none,
                prompted: .none
            )
        }

        let askLabels = collectAskFields(fields)
        guard !askLabels.isEmpty, let prompter = conditionalAccessPrompter else {
            // No Ask fields or no prompter → allow all Ask fields (fallback; not user-confirmed).
            return ConditionalFieldResolution(
                fields: GrantFields(
                    subjectMode: fields.subjectMode == .ask ? .on : fields.subjectMode,
                    fromMode: fields.fromMode == .ask ? .on : fields.fromMode,
                    toMode: fields.toMode == .ask ? .on : fields.toMode,
                    ccMode: fields.ccMode == .ask ? .on : fields.ccMode,
                    dateMode: fields.dateMode == .ask ? .on : fields.dateMode,
                    bodyMode: fields.bodyMode == .ask ? .on : fields.bodyMode,
                    attachmentMetadataMode: fields.attachmentMetadataMode == .ask
                        ? .on : fields.attachmentMetadataMode,
                    attachmentContentMode: fields.attachmentContentMode == .ask
                        ? .on : fields.attachmentContentMode
                ),
                confirmed: .none,
                blocked: .none,
                prompted: .none
            )
        }

        let context = ConditionalAccessPromptContext(
            agentName: agentName,
            accountID: message.accountID,
            placement: message.placement,
            messageID: message.id,
            internetMessageID: message.internetMessageID,
            requestedFields: askLabels,
            fieldPreviews: Self.fieldPreviews(message: message, askLabels: askLabels),
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
        let decision = await prompter(context)
        let resolvedMode: FieldAccessMode = decision == .allow ? .on : .off
        return ConditionalFieldResolution(
            fields: GrantFields(
                subjectMode: fields.subjectMode == .ask ? resolvedMode : fields.subjectMode,
                fromMode: fields.fromMode == .ask ? resolvedMode : fields.fromMode,
                toMode: fields.toMode == .ask ? resolvedMode : fields.toMode,
                ccMode: fields.ccMode == .ask ? resolvedMode : fields.ccMode,
                dateMode: fields.dateMode == .ask ? resolvedMode : fields.dateMode,
                bodyMode: fields.bodyMode == .ask ? resolvedMode : fields.bodyMode,
                attachmentMetadataMode: fields.attachmentMetadataMode == .ask
                    ? resolvedMode : fields.attachmentMetadataMode,
                attachmentContentMode: fields.attachmentContentMode == .ask
                    ? resolvedMode : fields.attachmentContentMode
            ),
            confirmed: decision == .allow ? askMask : .none,
            blocked: decision == .block ? askMask : .none,
            prompted: askMask
        )
    }

    private static let bodyPreviewCap = 2_000

    private static func fieldPreviews(
        message: ReadMessage,
        askLabels: [String]
    ) -> [ConditionalFieldPreviewLine] {
        askLabels.map { label in
            ConditionalFieldPreviewLine(
                label: label,
                value: previewValue(for: label, message: message)
            )
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
            switch message.body {
            case .text(let text):
                if let html = message.htmlBody,
                   !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                {
                    raw = MailMIME.plainText(fromHTML: html)
                } else if text.contains("<") || text.contains("body {") || text.contains("&zwnj;") {
                    raw = MailMIME.plainText(fromHTML: text)
                } else {
                    raw = MailMIME.decodeHTMLEntities(text)
                }
            case .notAvailable, .notGranted:
                raw = ""
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
        guard !trimmed.isEmpty else { return "(empty)" }
        if label == "Body", trimmed.count > bodyPreviewCap {
            return String(trimmed.prefix(bodyPreviewCap)) + "…"
        }
        return trimmed
    }

    /// Modes that are Ask, expressed as `.on` bits for mask/union helpers.
    private static func askMask(_ fields: GrantFields) -> GrantFields {
        GrantFields(
            subjectMode: fields.subjectMode == .ask ? .on : .off,
            fromMode: fields.fromMode == .ask ? .on : .off,
            toMode: fields.toMode == .ask ? .on : .off,
            ccMode: fields.ccMode == .ask ? .on : .off,
            dateMode: fields.dateMode == .ask ? .on : .off,
            bodyMode: fields.bodyMode == .ask ? .on : .off,
            attachmentMetadataMode: fields.attachmentMetadataMode == .ask ? .on : .off,
            attachmentContentMode: fields.attachmentContentMode == .ask ? .on : .off
        )
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
            guard let grant = effectiveGrant(for: probe, agentID: agent.id) else {
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
            let rawFields = grant.fields
            let resolution = await resolveConditionalFields(
                rawFields,
                agentName: agent.name,
                message: message
            )
            let fields = resolution.fields
            let granted = message.applying(fields)
            var (sanitized, subjectField, bodyField) = sanitizeGet(granted, fields: fields)
            if resolution.prompted.subject {
                subjectField = subjectField.markingConditionalPrompt(
                    allowed: resolution.confirmed.subject
                )
            }
            if resolution.prompted.body {
                bodyField = bodyField.markingConditionalPrompt(
                    allowed: resolution.confirmed.body
                )
            }
            let conditionalLabels = Self.conditionalFieldLabels(resolution.confirmed)
            let blockedLabels = Self.conditionalFieldLabels(resolution.blocked)
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
                        appliedRules: grant.applied,
                        conditionalFields: resolution.confirmed,
                        conditionalBlockedFields: resolution.blocked
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
    ) throws -> AttachmentAccessResult {
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
            let resolvedName = message.attachments.first {
                $0.filename.lowercased() == filename.lowercased()
            }?.filename ?? filename

            let result: AttachmentAccessResult
            if !fields.attachmentContent {
                result = AttachmentAccessResult(
                    accountID: accountID,
                    placement: placement,
                    id: id,
                    filename: resolvedName,
                    byteCount: message.attachments.first {
                        $0.filename.lowercased() == filename.lowercased()
                    }?.byteCount,
                    isPartial: message.isPartial,
                    attachmentContentAccess: .notGranted,
                    note: "Attachment content omitted: the active grant does not allow attachment content. Ask the user to enable Attachment Content on the grant."
                )
            } else if let meta = message.attachments.first(where: {
                $0.filename.lowercased() == filename.lowercased()
            }) {
                if meta.byteCount > Self.attachmentByteLimit {
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
            } else {
                let note: String
                if message.attachments.isEmpty {
                    note = message.isPartial
                        ? "Attachment not available. Message is partial; Apple Mail may not have downloaded this part."
                        : "Attachment not available for this message."
                } else {
                    note = "No attachment named \"\(filename)\" on this message."
                }
                result = AttachmentAccessResult(
                    accountID: accountID,
                    placement: placement,
                    id: id,
                    filename: filename,
                    isPartial: message.isPartial,
                    attachmentContentAccess: .notAvailable,
                    note: note
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

    public func listPlacements(credential: String?) throws -> [Placement] {
        let started = Date()
        let agent = try authenticate(credential)
        do {
            let placements = grants.filter(try read.listPlacements(), agentID: agent.id)
            record(
                kind: .listPlacements,
                agent: agent,
                started: started,
                detail: "list_placements",
                requestSummary: AuditJSON.json([:] as [String: Any]),
                responseSummary: AuditJSON.json(AuditJSON.placements(placements)),
                placements: placements.map {
                    AuditPlacementRef(accountID: $0.accountID, placement: $0.id)
                }
            )
            return placements
        } catch {
            record(
                kind: .listPlacements,
                agent: agent,
                started: started,
                detail: "list_placements",
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
