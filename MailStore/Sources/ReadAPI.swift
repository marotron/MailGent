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
            rawBody: mail.rawBody,
            attachments: mail.attachments,
            cc: mail.cc
        )
    }

    /// Arrivals from the last ingest pass (`update`'s `newCount`), newest-first.
    /// Trash/Junk copies and identity-only reindexes are omitted.
    public func listNew(
        limit: Int = 100,
        cursor: String? = nil
    ) throws -> Page<IndexedMessage> {
        let offset = cursor.flatMap(Int.init) ?? 0
        let clamped = min(max(limit, 1), 100)
        let fetched = try index.listNewMessages(
            limit: clamped + 1,
            offset: max(offset, 0)
        )
        let hasMore = fetched.count > clamped
        return Page(
            items: Array(fetched.prefix(clamped)),
            nextCursor: hasMore ? String(max(offset, 0) + clamped) : nil
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

    public func freshness() throws -> IndexFreshness {
        try index.freshness()
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
    /// Granted, but no plain-text body (empty message or HTML-only).
    case notAvailable
    /// Active grant does not allow body access.
    case notGranted
}

public struct ReadMessage: Equatable, Sendable {
    public let id: String
    public let accountID: String
    public let placement: String
    public let from: String
    public let to: String
    public let cc: String
    public let date: String
    public let subject: String
    public let body: ReadBody
    /// Decoded HTML when present; Pretty prefers this over plain text.
    public let htmlBody: String?
    /// Original MIME body block; empty when only the index row is available.
    public let rawBody: String
    public let isPartial: Bool
    public let attachments: [MailAttachment]
    /// False when the active grant omitted attachment names.
    public let attachmentMetadataGranted: Bool
    /// Leak-guard access metadata for MCP JSON and audit (nil when scan skipped).
    public let leakGuardAccess: ReadMessageAccess?

    init(
        _ message: IndexedMessage,
        prettyBody: String? = nil,
        htmlBody: String? = nil,
        rawBody: String = "",
        attachments: [MailAttachment] = [],
        cc: String? = nil,
        leakGuardAccess: ReadMessageAccess? = nil
    ) {
        self.id = message.id
        self.accountID = message.accountID
        self.placement = message.placement
        self.from = message.from
        self.to = message.to
        self.cc = cc ?? message.cc
        self.date = message.date
        self.subject = message.subject
        let text = prettyBody ?? message.body
        self.body = text.isEmpty ? .notAvailable : .text(text)
        self.htmlBody = htmlBody
        self.rawBody = rawBody
        self.isPartial = message.isPartial
        self.attachments = attachments
        self.attachmentMetadataGranted = true
        self.leakGuardAccess = leakGuardAccess
    }

    /// Omits body/html/raw under agent field caps (`.notGranted`).
    public func omittingBody() -> ReadMessage {
        applying(GrantFields(envelope: true, body: false))
    }

    /// Applies field caps: denied header values become empty; denied body → `.notGranted`.
    public func applying(_ fields: GrantFields) -> ReadMessage {
        ReadMessage(
            id: id,
            accountID: accountID,
            placement: placement,
            from: fields.from ? from : "",
            to: fields.to ? to : "",
            cc: fields.cc ? cc : "",
            date: fields.date ? date : "",
            subject: fields.subject ? subject : "",
            body: fields.body ? body : .notGranted,
            htmlBody: fields.body ? htmlBody : nil,
            rawBody: fields.body ? rawBody : "",
            isPartial: isPartial,
            attachments: fields.attachmentMetadata ? attachments : [],
            attachmentMetadataGranted: fields.attachmentMetadata,
            leakGuardAccess: leakGuardAccess
        )
    }

    func withLeakGuardAccess(_ access: ReadMessageAccess) -> ReadMessage {
        ReadMessage(
            id: id,
            accountID: accountID,
            placement: placement,
            from: from,
            to: to,
            cc: cc,
            date: date,
            subject: subject,
            body: body,
            htmlBody: htmlBody,
            rawBody: rawBody,
            isPartial: isPartial,
            attachments: attachments,
            attachmentMetadataGranted: attachmentMetadataGranted,
            leakGuardAccess: access
        )
    }

    func withSanitizedSubject(_ text: String) -> ReadMessage {
        ReadMessage(
            id: id,
            accountID: accountID,
            placement: placement,
            from: from,
            to: to,
            cc: cc,
            date: date,
            subject: text,
            body: body,
            htmlBody: htmlBody,
            rawBody: rawBody,
            isPartial: isPartial,
            attachments: attachments,
            attachmentMetadataGranted: attachmentMetadataGranted,
            leakGuardAccess: leakGuardAccess
        )
    }

    func withSanitizedBody(_ body: ReadBody) -> ReadMessage {
        ReadMessage(
            id: id,
            accountID: accountID,
            placement: placement,
            from: from,
            to: to,
            cc: cc,
            date: date,
            subject: subject,
            body: body,
            htmlBody: htmlBody,
            rawBody: rawBody,
            isPartial: isPartial,
            attachments: attachments,
            attachmentMetadataGranted: attachmentMetadataGranted,
            leakGuardAccess: leakGuardAccess
        )
    }

    private init(
        id: String,
        accountID: String,
        placement: String,
        from: String,
        to: String,
        cc: String,
        date: String,
        subject: String,
        body: ReadBody,
        htmlBody: String?,
        rawBody: String,
        isPartial: Bool,
        attachments: [MailAttachment],
        attachmentMetadataGranted: Bool,
        leakGuardAccess: ReadMessageAccess?
    ) {
        self.id = id
        self.accountID = accountID
        self.placement = placement
        self.from = from
        self.to = to
        self.cc = cc
        self.date = date
        self.subject = subject
        self.body = body
        self.htmlBody = htmlBody
        self.rawBody = rawBody
        self.isPartial = isPartial
        self.attachments = attachments
        self.attachmentMetadataGranted = attachmentMetadataGranted
        self.leakGuardAccess = leakGuardAccess
    }

    /// HTML for Pretty when it is a complete alternative; nil when it is a closed prefix of plain.
    public var prettyHTMLBody: String? {
        guard let htmlBody,
              !htmlBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        switch body {
        case .text(let plain):
            if MailMIME.htmlLooksLikePrefix(html: htmlBody, plain: plain) {
                return nil
            }
            return htmlBody
        case .notAvailable, .notGranted:
            return htmlBody
        }
    }
}

public struct Page<T: Equatable>: Equatable {
    public let items: [T]
    public let nextCursor: String?
}
