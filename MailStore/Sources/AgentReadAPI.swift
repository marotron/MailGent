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
        let agent = try authenticate(credential)
        let page = try read.list(
            limit: limit,
            cursor: cursor,
            accountID: accountID,
            placement: placement
        )
        return filterPage(page, agentID: agent.id, limit: limit)
    }

    public func search(
        _ query: String,
        credential: String?,
        limit: Int = 25,
        cursor: String? = nil,
        accountID: String? = nil,
        placement: String? = nil
    ) throws -> Page<IndexedMessage> {
        let agent = try authenticate(credential)
        // Over-fetch then deny-filter so counts/pages never include denied rows.
        let page = try read.search(
            query,
            limit: 100,
            cursor: cursor,
            accountID: accountID,
            placement: placement
        )
        audit?.append(
            AuditEntry(
                kind: .search,
                agentID: agent.id,
                agentName: agent.name,
                detail: query
            )
        )
        return filterPage(page, agentID: agent.id, limit: limit)
    }

    public func get(
        credential: String?,
        accountID: String,
        placement: String,
        id: String
    ) throws -> ReadMessage {
        let agent = try authenticate(credential)
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
            throw PairingError.unauthorized
        }
        audit?.append(
            AuditEntry(
                kind: .get,
                agentID: agent.id,
                agentName: agent.name,
                detail: "\(accountID)/\(placement)/\(id)"
            )
        )
        return message.applying(fields)
    }

    public func listPlacements(credential: String?) throws -> [Placement] {
        let agent = try authenticate(credential)
        return grants.filter(try read.listPlacements(), agentID: agent.id)
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
}
