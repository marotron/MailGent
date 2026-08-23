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
                    requestSummary: request,
                    outcome: .error("unauthorized")
                )
                throw PairingError.unauthorized
            }
            let granted = message.applying(fields)
            record(
                kind: .get,
                agent: agent,
                started: started,
                detail: path,
                requestSummary: request,
                responseSummary: AuditJSON.json(AuditJSON.messageDetail(granted)),
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
                detail: "listPlacements",
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
                detail: "listPlacements",
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
                detail: "new=\(outcome.newCount)",
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
}
