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
        return ReadMessage(indexed, prettyBody: mail.body, rawBody: mail.rawBody)
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
    /// Original MIME body block; empty when only the index row is available.
    public let rawBody: String
    public let isPartial: Bool

    init(_ message: IndexedMessage, prettyBody: String? = nil, rawBody: String = "") {
        self.id = message.id
        self.accountID = message.accountID
        self.placement = message.placement
        self.from = message.from
        self.to = message.to
        self.date = message.date
        self.subject = message.subject
        let text = prettyBody ?? message.body
        self.body = text.isEmpty ? .notAvailable : .text(text)
        self.rawBody = rawBody
        self.isPartial = message.isPartial
    }
}

public struct Page<T: Equatable>: Equatable {
    public let items: [T]
    public let nextCursor: String?
}
