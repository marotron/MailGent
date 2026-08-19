import Foundation

public struct ReadAPI {
    public let index: MailboxIndex

    public init(index: MailboxIndex) {
        self.index = index
    }

    public func list(limit: Int = 25, cursor: String? = nil) throws -> Page<IndexedMessage> {
        try page(index.allMessages(), limit: limit, cursor: cursor)
    }

    public func search(_ query: String, limit: Int = 25, cursor: String? = nil) throws -> Page<IndexedMessage> {
        try page(index.search(query), limit: limit, cursor: cursor)
    }

    public func get(accountID: String, placement: String, id: String) throws -> ReadMessage {
        ReadMessage(try index.get(accountID: accountID, placement: placement, id: id))
    }

    public func listPlacements() throws -> [Placement] {
        var seen = Set<Placement>()
        var placements: [Placement] = []
        for message in try index.allMessages() {
            let placement = Placement(accountID: message.accountID, id: message.placement)
            if seen.insert(placement).inserted {
                placements.append(placement)
            }
        }
        return placements
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
    public let isPartial: Bool

    init(_ message: IndexedMessage) {
        self.id = message.id
        self.accountID = message.accountID
        self.placement = message.placement
        self.from = message.from
        self.to = message.to
        self.date = message.date
        self.subject = message.subject
        self.body = message.body.isEmpty ? .notAvailable : .text(message.body)
        self.isPartial = message.isPartial
    }
}

public struct Page<T: Equatable>: Equatable {
    public let items: [T]
    public let nextCursor: String?
}

private func page<T>(_ items: [T], limit: Int, cursor: String?) -> Page<T> {
    let clamped = min(max(limit, 1), 100)
    let offset = cursor.flatMap(Int.init) ?? 0
    let slice = Array(items.dropFirst(max(offset, 0)).prefix(clamped))
    let next = max(offset, 0) + slice.count
    return Page(items: slice, nextCursor: next < items.count ? String(next) : nil)
}
