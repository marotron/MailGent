import Foundation

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
    public var muteConditionalAccessPrompts: Bool

    public init(
        read: ReadAPI,
        pairing: Pairing,
        grants: GrantGate = GrantGate(),
        leakGuard: OutboundLeakGuard = OutboundLeakGuard(),
        rules: RuleStore = RuleStore(),
        audit: AuditLog? = nil,
        muteConditionalAccessPrompts: Bool = false
    ) {
        self.read = read
        self.pairing = pairing
        self.grants = grants
        self.leakGuard = leakGuard
        self.rules = rules
        self.audit = audit
        self.muteConditionalAccessPrompts = muteConditionalAccessPrompts
    }

    @discardableResult
    public func authenticate(_ credential: String?) throws -> PairedAgent {
        try pairing.authenticate(credential: credential)
    }
    
    /// Resolves Ask mode fields based on the global mute setting.
    /// When muted: Ask → denied (fail-closed).
    /// When not muted: Ask → allowed (TODO: actual prompt in future).
    private func resolveConditionalFields(_ fields: GrantFields) -> GrantFields {
        if !muteConditionalAccessPrompts {
            // TODO: Implement actual prompt dialog. For now, treat Ask as allowed when not muted.
            return GrantFields(
                subjectMode: fields.subjectMode == .ask ? .on : fields.subjectMode,
                fromMode: fields.fromMode == .ask ? .on : fields.fromMode,
                toMode: fields.toMode == .ask ? .on : fields.toMode,
                ccMode: fields.ccMode == .ask ? .on : fields.ccMode,
                dateMode: fields.dateMode == .ask ? .on : fields.dateMode,
                bodyMode: fields.bodyMode == .ask ? .on : fields.bodyMode,
                attachmentMetadataMode: fields.attachmentMetadataMode == .ask ? .on : fields.attachmentMetadataMode,
                attachmentContentMode: fields.attachmentContentMode == .ask ? .on : fields.attachmentContentMode
            )
        } else {
            // Muted: Ask → Off (fail-closed)
            return GrantFields(
                subjectMode: fields.subjectMode == .ask ? .off : fields.subjectMode,
                fromMode: fields.fromMode == .ask ? .off : fields.fromMode,
                toMode: fields.toMode == .ask ? .off : fields.toMode,
                ccMode: fields.ccMode == .ask ? .off : fields.ccMode,
                dateMode: fields.dateMode == .ask ? .off : fields.dateMode,
                bodyMode: fields.bodyMode == .ask ? .off : fields.bodyMode,
                attachmentMetadataMode: fields.attachmentMetadataMode == .ask ? .off : fields.attachmentMetadataMode,
                attachmentContentMode: fields.attachmentContentMode == .ask ? .off : fields.attachmentContentMode
            )
        }
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
    ) throws -> ReadMessage {
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
            let fields = resolveConditionalFields(rawFields)
            let granted = message.applying(fields)
            let (sanitized, subjectField, bodyField) = sanitizeGet(granted, fields: fields)
            let access = ReadMessageAccess(subject: subjectField, body: bodyField)
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
                        appliedRules: grant.applied
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
