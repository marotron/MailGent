import Foundation

/// Optional Assembly-C context on `propose_send` (experimental).
public struct SendProposalContext: Equatable, Sendable {
    public static let maxEvents = 40

    public let casePath: String
    public let caseLabel: String
    public let events: [SendProposalEventRef]
    public let links: [SendProposalLink]

    public init(
        casePath: String,
        caseLabel: String,
        events: [SendProposalEventRef],
        links: [SendProposalLink] = []
    ) {
        self.casePath = casePath
        self.caseLabel = caseLabel
        self.events = events
        self.links = links
    }

    /// Parse MCP `context` object. Throws on schema / path / cap errors.
    public static func parse(_ raw: [String: Any]) throws -> SendProposalContext {
        guard let casePathRaw = raw["casePath"] as? String else {
            throw SendProposalContextError.missingField("casePath")
        }
        let casePath = try sanitizeRelativePath(casePathRaw, field: "casePath")
        let caseLabel: String
        if let label = raw["caseLabel"] as? String,
           !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            caseLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            caseLabel = (casePath as NSString).lastPathComponent
        }

        guard let eventsRaw = raw["events"] as? [[String: Any]] else {
            throw SendProposalContextError.missingField("events")
        }
        guard eventsRaw.count <= maxEvents else {
            throw SendProposalContextError.tooManyEvents(eventsRaw.count)
        }

        var seenIDs = Set<String>()
        var events: [SendProposalEventRef] = []
        events.reserveCapacity(eventsRaw.count)
        for (index, eventRaw) in eventsRaw.enumerated() {
            let event = try SendProposalEventRef.parse(eventRaw, index: index)
            guard seenIDs.insert(event.id).inserted else {
                throw SendProposalContextError.duplicateEventID(event.id)
            }
            events.append(event)
        }

        let linksRaw = raw["links"] as? [[String: Any]] ?? []
        let links = try linksRaw.map { try SendProposalLink.parse($0) }

        return SendProposalContext(
            casePath: casePath,
            caseLabel: caseLabel,
            events: events,
            links: links
        )
    }

    /// `nil` / `NSNull` → nil. Dictionary → parse. Other types → error.
    public static func parseOptional(_ value: Any?) throws -> SendProposalContext? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        guard let dict = value as? [String: Any] else {
            throw SendProposalContextError.invalidType("context")
        }
        return try parse(dict)
    }

    /// Relative path under vault root: no absolute, no `..`, no empty segments.
    public static func sanitizeRelativePath(_ raw: String, field: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SendProposalContextError.invalidPath(field: field, path: raw)
        }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            throw SendProposalContextError.invalidPath(field: field, path: raw)
        }
        // Reject Windows-style drive / URL schemes early.
        if trimmed.contains("://") || (trimmed.count >= 2 && trimmed[trimmed.index(trimmed.startIndex, offsetBy: 1)] == ":") {
            throw SendProposalContextError.invalidPath(field: field, path: raw)
        }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            throw SendProposalContextError.invalidPath(field: field, path: raw)
        }
        return parts.joined(separator: "/")
    }
}

public struct SendProposalEventRef: Equatable, Sendable {
    public let id: String
    public let kind: SendProposalEventKind
    public let scope: SendProposalEventScope
    public let ownership: SendProposalEventOwnership
    public let party: SendProposalParty?
    public let at: Date
    public let summary: String
    public let source: SendProposalEventSource

    public init(
        id: String,
        kind: SendProposalEventKind,
        scope: SendProposalEventScope,
        ownership: SendProposalEventOwnership,
        party: SendProposalParty? = nil,
        at: Date,
        summary: String,
        source: SendProposalEventSource
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.ownership = ownership
        self.party = party
        self.at = at
        self.summary = summary
        self.source = source
    }

    static func parse(_ raw: [String: Any], index: Int) throws -> SendProposalEventRef {
        guard let id = raw["id"] as? String,
              !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SendProposalContextError.missingField("events[\(index)].id")
        }
        let idTrimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let kindRaw = raw["kind"] as? String,
              let kind = SendProposalEventKind(rawValue: kindRaw)
        else {
            throw SendProposalContextError.unknownKind(raw["kind"] as? String ?? "")
        }
        guard let scopeRaw = raw["scope"] as? String,
              let scope = SendProposalEventScope(rawValue: scopeRaw)
        else {
            throw SendProposalContextError.invalidField("events[\(index)].scope")
        }
        guard let ownershipRaw = raw["ownership"] as? String,
              let ownership = SendProposalEventOwnership(rawValue: ownershipRaw)
        else {
            throw SendProposalContextError.invalidField("events[\(index)].ownership")
        }
        guard let atRaw = raw["at"] as? String,
              let at = Self.parseISO8601(atRaw)
        else {
            throw SendProposalContextError.invalidField("events[\(index)].at")
        }
        guard let summary = raw["summary"] as? String else {
            throw SendProposalContextError.missingField("events[\(index)].summary")
        }

        var party: SendProposalParty?
        if let partyRaw = raw["party"] as? [String: Any] {
            party = try SendProposalParty.parse(partyRaw, field: "events[\(index)].party")
        } else if ownership == .them || ownership == .both {
            throw SendProposalContextError.missingField("events[\(index)].party")
        }

        guard let sourceRaw = raw["source"] as? [String: Any] else {
            throw SendProposalContextError.missingField("events[\(index)].source")
        }
        let source = try SendProposalEventSource.parse(sourceRaw, kind: kind, index: index)

        return SendProposalEventRef(
            id: idTrimmed,
            kind: kind,
            scope: scope,
            ownership: ownership,
            party: party,
            at: at,
            summary: summary,
            source: source
        )
    }

    private static func parseISO8601(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: raw)
    }
}

public enum SendProposalEventKind: String, Equatable, Sendable {
    case mail
    case phone
    case video
    case note
    case log
}

public enum SendProposalEventScope: String, Equatable, Sendable {
    case `private`
    case shared
}

public enum SendProposalEventOwnership: String, Equatable, Sendable {
    case them
    case you
    case both
}

public struct SendProposalParty: Equatable, Sendable {
    public let name: String
    public let initials: String?

    public init(name: String, initials: String? = nil) {
        self.name = name
        self.initials = initials
    }

    static func parse(_ raw: [String: Any], field: String) throws -> SendProposalParty {
        guard let name = raw["name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw SendProposalContextError.missingField("\(field).name")
        }
        let initials = (raw["initials"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SendProposalParty(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            initials: (initials?.isEmpty == false) ? initials : nil
        )
    }
}

public enum SendProposalEventSource: Equatable, Sendable {
    case mail(accountID: String, placement: String, id: String)
    case vault(path: String, anchor: String?)

    static func parse(
        _ raw: [String: Any],
        kind: SendProposalEventKind,
        index: Int
    ) throws -> SendProposalEventSource {
        let hasMail = raw["mail"] != nil
        let hasVault = raw["vault"] != nil
        switch kind {
        case .mail:
            guard hasMail, !hasVault, let mail = raw["mail"] as? [String: Any] else {
                throw SendProposalContextError.sourceMismatch(kind: kind.rawValue, index: index)
            }
            guard let accountID = mail["accountID"] as? String,
                  !accountID.isEmpty,
                  let placement = mail["placement"] as? String,
                  !placement.isEmpty,
                  let id = mail["id"] as? String,
                  !id.isEmpty
            else {
                throw SendProposalContextError.invalidField("events[\(index)].source.mail")
            }
            return .mail(accountID: accountID, placement: placement, id: id)

        case .phone, .video, .note, .log:
            guard hasVault, !hasMail, let vault = raw["vault"] as? [String: Any] else {
                throw SendProposalContextError.sourceMismatch(kind: kind.rawValue, index: index)
            }
            guard let pathRaw = vault["path"] as? String else {
                throw SendProposalContextError.missingField("events[\(index)].source.vault.path")
            }
            let path = try SendProposalContext.sanitizeRelativePath(
                pathRaw,
                field: "events[\(index)].source.vault.path"
            )
            let anchor = (vault["anchor"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .vault(
                path: path,
                anchor: (anchor?.isEmpty == false) ? anchor : nil
            )
        }
    }
}

public struct SendProposalLink: Equatable, Sendable {
    public let from: String
    public let to: String
    public let rel: String
    public let label: String?

    public init(from: String, to: String, rel: String, label: String? = nil) {
        self.from = from
        self.to = to
        self.rel = rel
        self.label = label
    }

    static func parse(_ raw: [String: Any]) throws -> SendProposalLink {
        guard let from = raw["from"] as? String, !from.isEmpty,
              let to = raw["to"] as? String, !to.isEmpty,
              let rel = raw["rel"] as? String, !rel.isEmpty
        else {
            throw SendProposalContextError.invalidField("links")
        }
        let label = (raw["label"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SendProposalLink(
            from: from,
            to: to,
            rel: rel,
            label: (label?.isEmpty == false) ? label : nil
        )
    }
}

public enum SendProposalContextError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingField(String)
    case invalidField(String)
    case invalidType(String)
    case invalidPath(field: String, path: String)
    case unknownKind(String)
    case tooManyEvents(Int)
    case duplicateEventID(String)
    case sourceMismatch(kind: String, index: Int)

    public var description: String {
        switch self {
        case .missingField(let field):
            return "context missing \(field)"
        case .invalidField(let field):
            return "context invalid \(field)"
        case .invalidType(let field):
            return "context \(field) must be an object"
        case .invalidPath(let field, let path):
            return "context \(field) must be a relative path under the vault root (got \"\(path)\")"
        case .unknownKind(let kind):
            return "context unknown kind \"\(kind)\""
        case .tooManyEvents(let count):
            return "context events exceeds \(SendProposalContext.maxEvents) (got \(count))"
        case .duplicateEventID(let id):
            return "context duplicate event id \"\(id)\""
        case .sourceMismatch(let kind, let index):
            return "context events[\(index)] kind \(kind) has mismatched source"
        }
    }
}

