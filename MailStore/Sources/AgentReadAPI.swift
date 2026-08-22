import Foundation

/// ReadAPI surface for paired agents. Every call requires proof of possession.
/// Results are deny-filtered through GrantGate (no grants → empty / not_available).
public struct AgentReadAPI {
    public let read: ReadAPI
    public let pairing: Pairing
    public let grants: GrantGate
    public let audit: AuditLog?

    public init(
        read: ReadAPI,
        pairing: Pairing,
        grants: GrantGate = GrantGate(),
        audit: AuditLog? = nil
    ) {
        self.read = read
        self.pairing = pairing
        self.grants = grants
        self.audit = audit
    }

    @discardableResult
    public func authenticate(_ credential: String?) throws -> PairedAgent {
        try pairing.authenticate(credential: credential)
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
        let request = Self.listRequestSummary(
            limit: limit,
            cursor: cursor,
            accountID: accountID,
            placement: placement
        )
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
                responseSummary: "\(filtered.items.count) messages",
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
        let request = Self.searchRequestSummary(
            query: query,
            limit: limit,
            cursor: cursor,
            accountID: accountID,
            placement: placement
        )
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
                responseSummary: "\(filtered.items.count) messages",
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
        do {
            let message = try read.get(accountID: accountID, placement: placement, id: id)
            let probe = IndexedMessage(
                id: message.id,
                accountID: message.accountID,
                placement: message.placement,
                from: message.from,
                to: message.to,
                date: message.date,
                subject: message.subject,
                body: "",
                isPartial: message.isPartial
            )
            guard let fields = grants.effectiveFields(for: probe, agentID: agent.id) else {
                record(
                    kind: .get,
                    agent: agent,
                    started: started,
                    detail: path,
                    requestSummary: path,
                    outcome: .error("unauthorized")
                )
                throw PairingError.unauthorized
            }
            let granted = message.applying(fields)
            let bodyAccess: String
            switch granted.body {
            case .text, .notAvailable:
                bodyAccess = "granted"
            case .notGranted:
                bodyAccess = "not_granted"
            }
            record(
                kind: .get,
                agent: agent,
                started: started,
                detail: path,
                requestSummary: path,
                responseSummary: "bodyAccess=\(bodyAccess)",
                messages: [AuditMessageRef(granted, fields: fields)]
            )
            return granted
        } catch let error as PairingError where error == .unauthorized {
            throw error
        } catch {
            record(
                kind: .get,
                agent: agent,
                started: started,
                detail: path,
                requestSummary: path,
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
                detail: "listPlacements",
                requestSummary: "listPlacements",
                responseSummary: "\(placements.count) placements",
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
                detail: "listPlacements",
                requestSummary: "listPlacements",
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
            var parts = ["indexed=\(freshness.indexedCount)"]
            if freshness.lastIngestAt != nil {
                parts.append("lastIngest=set")
            }
            record(
                kind: .status,
                agent: agent,
                started: started,
                detail: "status",
                requestSummary: "status",
                responseSummary: parts.joined(separator: " ")
            )
            return freshness
        } catch {
            record(
                kind: .status,
                agent: agent,
                started: started,
                detail: "status",
                requestSummary: "status",
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    public func updateIndex(credential: String?, updater: any IndexUpdating) throws -> IndexUpdateOutcome {
        let started = Date()
        let agent = try authenticate(credential)
        do {
            let outcome = try updater.update()
            record(
                kind: .updateIndex,
                agent: agent,
                started: started,
                detail: "new=\(outcome.newCount)",
                requestSummary: "update",
                responseSummary: "new=\(outcome.newCount) indexed=\(outcome.freshness.indexedCount)"
            )
            return outcome
        } catch {
            record(
                kind: .updateIndex,
                agent: agent,
                started: started,
                detail: "update",
                requestSummary: "update",
                outcome: .error(String(describing: error))
            )
            throw error
        }
    }

    private func filterPage(
        _ page: Page<IndexedMessage>,
        agentID: String,
        limit: Int
    ) -> Page<IndexedMessage> {
        let clamped = min(max(limit, 1), 100)
        let allowed = grants.filter(page.items, agentID: agentID)
        let items = Array(allowed.prefix(clamped))
        // Cursor semantics under filtering are approximate for first ship; denied rows
        // never appear and never inflate the returned page.
        let next = allowed.count > clamped ? page.nextCursor : nil
        return Page(items: items, nextCursor: next)
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
            AuditMessageRef(
                item,
                fields: grants.effectiveFields(for: item, agentID: agentID) ?? .headersOnly
            )
        }
    }

    private static func listRequestSummary(
        limit: Int,
        cursor: String?,
        accountID: String?,
        placement: String?
    ) -> String {
        var parts = ["limit=\(limit)"]
        if cursor != nil { parts.append("cursor") }
        if let accountID { parts.append("account=\(accountID)") }
        if let placement { parts.append("placement=\(placement)") }
        return parts.joined(separator: " ")
    }

    private static func searchRequestSummary(
        query: String,
        limit: Int,
        cursor: String?,
        accountID: String?,
        placement: String?
    ) -> String {
        var parts = ["q=\(query)", "limit=\(limit)"]
        if cursor != nil { parts.append("cursor") }
        if let accountID { parts.append("account=\(accountID)") }
        if let placement { parts.append("placement=\(placement)") }
        return parts.joined(separator: " ")
    }
}
