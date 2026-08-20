import Foundation

public struct ReadAPI {
    public let index: MailboxIndex

    public init(index: MailboxIndex) {
        self.index = index
    }

    public func list(
        limit: Int = 25,
        cursor: String? = nil,
        accountID: String? = nil,
        placement: String? = nil
    ) throws -> Page<IndexedMessage> {
        let offset = cursor.flatMap(Int.init) ?? 0
        let clamped = min(max(limit, 1), 100)
        let fetched = try index.listMessages(
            limit: clamped + 1,
            offset: max(offset, 0),
            accountID: accountID,
            placement: placement
        )
        let hasMore = fetched.count > clamped
        return Page(
            items: Array(fetched.prefix(clamped)),
            nextCursor: hasMore ? String(max(offset, 0) + clamped) : nil
        )
    }

    public func search(
        _ query: String,
        limit: Int = 25,
        cursor: String? = nil,
        accountID: String? = nil,
        placement: String? = nil
    ) throws -> Page<IndexedMessage> {
        let offset = cursor.flatMap(Int.init) ?? 0
        let clamped = min(max(limit, 1), 100)
        let fetched = try index.searchMessages(
            query,
            limit: clamped + 1,
            offset: max(offset, 0),
            accountID: accountID,
            placement: placement
        )
        let hasMore = fetched.count > clamped
        return Page(
            items: Array(fetched.prefix(clamped)),
            nextCursor: hasMore ? String(max(offset, 0) + clamped) : nil
        )
    }

    public func get(accountID: String, placement: String, id: String) throws -> ReadMessage {
        let indexed = try index.get(accountID: accountID, placement: placement, id: id)
        guard let mail = try? index.store.message(accountID: accountID, mailbox: placement, id: id) else {
            return ReadMessage(indexed)
        }
        return ReadMessage(
            indexed,
            prettyBody: mail.body,
            htmlBody: mail.htmlBody,
            rawBody: mail.rawBody
        )
    }

    public func listPlacements() throws -> [Placement] {
        try index.distinctPlacements().map { Placement(accountID: $0.accountID, id: $0.placement) }
    }

    public func totalIndexed() throws -> Int {
        try index.messageCount()
    }

    public func placementIndexedCounts() throws -> [String: Int] {
        try index.placementIndexedCounts()
    }
}

public struct Placement: Hashable, Sendable {
    public let accountID: String
    public let id: String

    public init(accountID: String, id: String) {
        self.accountID = accountID
        self.id = id
    }
}

public enum ReadBody: Equatable, Sendable {
    case text(String)
    case notAvailable
}

public struct ReadMessage: Equatable, Sendable {
    public let id: String
    public let accountID: String
    public let placement: String
    public let from: String
    public let to: String
    public let date: String
    public let subject: String
    public let body: ReadBody
    /// Decoded HTML when present; Pretty prefers this over plain text.
    public let htmlBody: String?
    /// Original MIME body block; empty when only the index row is available.
    public let rawBody: String
    public let isPartial: Bool

    init(
        _ message: IndexedMessage,
        prettyBody: String? = nil,
        htmlBody: String? = nil,
        rawBody: String = ""
    ) {
        self.id = message.id
        self.accountID = message.accountID
        self.placement = message.placement
        self.from = message.from
        self.to = message.to
        self.date = message.date
        self.subject = message.subject
        let text = prettyBody ?? message.body
        self.body = text.isEmpty ? .notAvailable : .text(text)
        self.htmlBody = htmlBody
        self.rawBody = rawBody
        self.isPartial = message.isPartial
    }

    /// Omits body/html/raw without hinting that content exists (agent field caps).
    public func omittingBody() -> ReadMessage {
        applying(GrantFields(envelope: true, body: false))
    }

    /// Applies field caps: denied header values become empty; denied body → `.notAvailable`.
    public func applying(_ fields: GrantFields) -> ReadMessage {
        ReadMessage(
            id: id,
            accountID: accountID,
            placement: placement,
            from: fields.from ? from : "",
            to: fields.to ? to : "",
            date: fields.date ? date : "",
            subject: fields.subject ? subject : "",
            body: fields.body ? body : .notAvailable,
            htmlBody: fields.body ? htmlBody : nil,
            rawBody: fields.body ? rawBody : "",
            isPartial: isPartial
        )
    }

    private init(
        id: String,
        accountID: String,
        placement: String,
        from: String,
        to: String,
        date: String,
        subject: String,
        body: ReadBody,
        htmlBody: String?,
        rawBody: String,
        isPartial: Bool
    ) {
        self.id = id
        self.accountID = accountID
        self.placement = placement
        self.from = from
        self.to = to
        self.date = date
        self.subject = subject
        self.body = body
        self.htmlBody = htmlBody
        self.rawBody = rawBody
        self.isPartial = isPartial
    }
}

public struct Page<T: Equatable>: Equatable {
    public let items: [T]
    public let nextCursor: String?
}
