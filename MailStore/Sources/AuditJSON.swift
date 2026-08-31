import Foundation

/// JSON payloads stored on `AuditEntry` request/response summaries.
/// Shape matches the MCP tool result the agent receives.
enum AuditJSON {
    static func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
              ),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    static func request(_ fields: [String: Any?]) -> String {
        var dict: [String: Any] = [:]
        for (key, value) in fields {
            guard let value else { continue }
            dict[key] = value
        }
        return json(dict)
    }

    static func freshness(
        _ freshness: IndexFreshness,
        extra: [String: Any] = [:]
    ) -> [String: Any] {
        var payload: [String: Any] = [
            "indexedCount": freshness.indexedCount
        ]
        if let lastIngestAt = freshness.lastIngestAt {
            payload["lastIngestAt"] = iso8601(lastIngestAt)
        }
        if let newestMessageDate = freshness.newestMessageDate {
            payload["newestMessageDate"] = newestMessageDate
        }
        for (key, value) in extra {
            payload[key] = value
        }
        return payload
    }

    static func update(_ outcome: IndexUpdateOutcome) -> [String: Any] {
        var payload = freshness(outcome.freshness)
        payload["newCount"] = outcome.newCount
        payload["removedCount"] = outcome.removedCount
        return payload
    }

    static func page(_ page: Page<IndexedMessage>) -> [String: Any] {
        var payload: [String: Any] = [
            "items": page.items.map(messageSummary),
            "count": page.items.count
        ]
        if let nextCursor = page.nextCursor {
            payload["nextCursor"] = nextCursor
        }
        return payload
    }

    static func placements(_ placements: [Placement]) -> [String: Any] {
        [
            "placements": placements.map { "\($0.accountID)/\($0.id)" }
        ]
    }

    static func messageSummary(_ message: IndexedMessage) -> [String: Any] {
        [
            "accountID": message.accountID,
            "placement": message.placement,
            "id": message.id,
            "subject": message.subject,
            "from": message.from,
            "date": message.date,
            "isPartial": message.isPartial
        ]
    }

    static func messageDetail(_ message: ReadMessage) -> [String: Any] {
        var payload: [String: Any] = [
            "id": message.id,
            "accountID": message.accountID,
            "placement": message.placement,
            "subject": message.subject,
            "from": message.from,
            "to": message.to,
            "cc": message.cc,
            "date": message.date,
            "isPartial": message.isPartial
        ]
        if let access = message.leakGuardAccess {
            payload["subjectAccess"] = access.subjectAccess.rawValue
            if let reason = access.subjectAccessReason {
                payload["subjectAccessReason"] = reason.rawValue
            }
            payload["bodyAccess"] = access.bodyAccess.rawValue
            if let reason = access.bodyAccessReason {
                payload["bodyAccessReason"] = reason.rawValue
            }
            if !access.sanitizedRules.isEmpty {
                payload["sanitizedRules"] = access.sanitizedRules
            }
            if access.stealth {
                payload["note"] =
                    "Some field values were substituted on device; the access log retains originals."
            }
        }
        switch message.body {
        case .text(let text):
            if message.leakGuardAccess == nil {
                payload["bodyAccess"] = "granted"
            }
            if message.leakGuardAccess?.bodyAccess != .withheldConfidential, !text.isEmpty {
                payload["body"] = text
            }
        case .notAvailable:
            if message.leakGuardAccess == nil {
                payload["bodyAccess"] = "granted"
            }
            if message.leakGuardAccess?.bodyAccess != .withheldConfidential,
               let html = message.prettyHTMLBody,
               !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                let plain = MailMIME.plainText(fromHTML: html)
                if !plain.isEmpty {
                    payload["body"] = plain
                }
            }
        case .notGranted:
            payload["bodyAccess"] = "not_granted"
            if message.leakGuardAccess == nil {
                payload["note"] =
                    "Body omitted: the active grant for this account does not allow body access. Ask the user to enable body on the grant before summarizing or quoting the message."
            }
        }
        if message.attachmentMetadataGranted {
            payload["attachmentAccess"] = "granted"
            payload["attachments"] = message.attachments.map { attachment in
                [
                    "filename": attachment.filename,
                    "byteCount": attachment.byteCount
                ] as [String: Any]
            }
        } else {
            payload["attachmentAccess"] = "not_granted"
        }
        return payload
    }

    static func version(_ version: DraftVersion) -> [String: Any] {
        [
            "draftID": version.draftID,
            "versionID": version.id,
            "label": version.label,
            "body": version.body
        ]
    }

    static func source(_ snapshot: MailSourceSnapshot) -> [String: Any] {
        [
            "source": snapshot.source.rawValue,
            "agentMayChangeSource": snapshot.agentMayChangeSource
        ]
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

extension AuditKind {
    init?(toolName: String) {
        switch toolName {
        case "search": self = .search
        case "list": self = .list
        case "list_new", "listNew": self = .listNew
        case "list_placements", "listPlacements": self = .listPlacements
        case "get": self = .get
        case "create_draft": self = .createDraft
        case "update_draft": self = .updateDraft
        case "status": self = .status
        case "update": self = .updateIndex
        case "set_source": self = .setSource
        default: return nil
        }
    }
}
