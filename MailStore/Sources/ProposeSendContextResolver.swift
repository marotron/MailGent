import Foundation

/// Mail content pulled for one context-thread mail row (soft-fail when nil).
public struct ProposeSendMailContent: Equatable, Sendable {
    public let subject: String
    public let from: String
    public let body: String?
    /// RFC Message-ID when available (for Open in Mail).
    public let internetMessageID: String?

    public init(
        subject: String,
        from: String,
        body: String? = nil,
        internetMessageID: String? = nil
    ) {
        self.subject = subject
        self.from = from
        self.body = body
        self.internetMessageID = internetMessageID
    }
}

/// How the human opens the original behind a context-thread card.
public enum ContextThreadOriginal: Equatable, Sendable {
    case mail(accountID: String, placement: String, id: String, internetMessageID: String?)
    case vault(relativePath: String)
}

public protocol ProposeSendMailFetching: Sendable {
    func fetchMail(accountID: String, placement: String, id: String) async -> ProposeSendMailContent?
}

public protocol ProposeSendVaultReading: Sendable {
    /// Read UTF-8 text under the Personal vault root. Path is already sanitized relative to root.
    func readVaultFile(relativePath: String) -> String?
}

/// One display row in the propose-send context thread (including synthetic draft).
public struct ContextThreadItem: Equatable, Sendable, Identifiable {
    public let id: String
    public let kind: SendProposalEventKind
    public let scope: SendProposalEventScope
    public let ownership: SendProposalEventOwnership
    public let party: SendProposalParty?
    public let at: Date
    public let summary: String
    /// Mail envelope meta (shown above the body divider).
    public let from: String?
    public let subject: String?
    /// Expanded detail (mail body / vault excerpt); nil when unavailable or empty.
    public let detail: String?
    public let unavailableReason: String?
    public let isDraft: Bool
    /// Open original in Apple Mail / Finder when present.
    public let original: ContextThreadOriginal?
    public let linkChips: [ContextThreadLinkChip]

    public init(
        id: String,
        kind: SendProposalEventKind,
        scope: SendProposalEventScope,
        ownership: SendProposalEventOwnership,
        party: SendProposalParty? = nil,
        at: Date,
        summary: String,
        from: String? = nil,
        subject: String? = nil,
        detail: String? = nil,
        unavailableReason: String? = nil,
        isDraft: Bool = false,
        original: ContextThreadOriginal? = nil,
        linkChips: [ContextThreadLinkChip] = []
    ) {
        self.id = id
        self.kind = kind
        self.scope = scope
        self.ownership = ownership
        self.party = party
        self.at = at
        self.summary = summary
        self.from = from
        self.subject = subject
        self.detail = detail
        self.unavailableReason = unavailableReason
        self.isDraft = isDraft
        self.original = original
        self.linkChips = linkChips
    }
}

public struct ContextThreadLinkChip: Equatable, Sendable {
    public let rel: String
    public let label: String
    public let peerID: String

    public init(rel: String, label: String, peerID: String) {
        self.rel = rel
        self.label = label
        self.peerID = peerID
    }
}

public struct ProposeSendResolvedContext: Equatable, Sendable {
    public let casePath: String
    public let caseLabel: String
    public let items: [ContextThreadItem]

    public init(casePath: String, caseLabel: String, items: [ContextThreadItem]) {
        self.casePath = casePath
        self.caseLabel = caseLabel
        self.items = items
    }
}

/// Resolves agent `context` refs into display models + synthetic draft (prefetch at confirm open).
public struct ProposeSendContextResolver: Sendable {
    public let mail: any ProposeSendMailFetching
    public let vault: any ProposeSendVaultReading

    public init(mail: any ProposeSendMailFetching, vault: any ProposeSendVaultReading) {
        self.mail = mail
        self.vault = vault
    }

    public func resolve(
        context: SendProposalContext,
        proposal: SendProposal
    ) async -> ProposeSendResolvedContext {
        let chipsByEvent = Self.linkChips(from: context.links)
        // Stable sort: `at` ascending, then agent order.
        let ordered = context.events.enumerated().sorted { lhs, rhs in
            if lhs.element.at != rhs.element.at {
                return lhs.element.at < rhs.element.at
            }
            return lhs.offset < rhs.offset
        }

        var items: [ContextThreadItem] = []
        items.reserveCapacity(ordered.count + 1)
        for (index, event) in ordered {
            _ = index
            let chips = chipsByEvent[event.id] ?? []
            switch event.source {
            case let .mail(accountID, placement, id):
                let original = ContextThreadOriginal.mail(
                    accountID: accountID,
                    placement: placement,
                    id: id,
                    internetMessageID: nil
                )
                let content = await mail.fetchMail(
                    accountID: accountID,
                    placement: placement,
                    id: id
                )
                if let content {
                    let messageID = content.internetMessageID?
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let resolvedOriginal = ContextThreadOriginal.mail(
                        accountID: accountID,
                        placement: placement,
                        id: id,
                        internetMessageID: (messageID?.isEmpty == false) ? messageID : nil
                    )
                    items.append(
                        ContextThreadItem(
                            id: event.id,
                            kind: event.kind,
                            scope: event.scope,
                            ownership: event.ownership,
                            party: event.party,
                            at: event.at,
                            summary: event.summary,
                            from: content.from.isEmpty ? nil : content.from,
                            subject: content.subject.isEmpty ? nil : content.subject,
                            detail: content.body.flatMap { $0.isEmpty ? nil : $0 },
                            original: resolvedOriginal,
                            linkChips: chips
                        )
                    )
                } else {
                    items.append(
                        ContextThreadItem(
                            id: event.id,
                            kind: event.kind,
                            scope: event.scope,
                            ownership: event.ownership,
                            party: event.party,
                            at: event.at,
                            summary: event.summary,
                            unavailableReason: "Mail unavailable",
                            original: original,
                            linkChips: chips
                        )
                    )
                }

            case let .vault(path, anchor):
                let relative = [context.casePath, path]
                    .filter { !$0.isEmpty }
                    .joined(separator: "/")
                let original = ContextThreadOriginal.vault(relativePath: relative)
                let text = vault.readVaultFile(relativePath: relative)
                if let text {
                    let detail = Self.vaultExcerpt(text, anchor: anchor)
                    items.append(
                        ContextThreadItem(
                            id: event.id,
                            kind: event.kind,
                            scope: event.scope,
                            ownership: event.ownership,
                            party: event.party,
                            at: event.at,
                            summary: event.summary,
                            detail: detail.isEmpty ? text : detail,
                            original: original,
                            linkChips: chips
                        )
                    )
                } else {
                    items.append(
                        ContextThreadItem(
                            id: event.id,
                            kind: event.kind,
                            scope: event.scope,
                            ownership: event.ownership,
                            party: event.party,
                            at: event.at,
                            summary: event.summary,
                            unavailableReason: "Vault file unavailable",
                            original: original,
                            linkChips: chips
                        )
                    )
                }
            }
        }

        items.append(
            ContextThreadItem(
                id: "draft",
                kind: .mail,
                scope: .shared,
                ownership: .you,
                at: Date.distantFuture,
                summary: proposal.subject.isEmpty ? "Draft" : proposal.subject,
                detail: proposal.body,
                isDraft: true
            )
        )

        return ProposeSendResolvedContext(
            casePath: context.casePath,
            caseLabel: context.caseLabel,
            items: items
        )
    }

    private static func linkChips(from links: [SendProposalLink]) -> [String: [ContextThreadLinkChip]] {
        var map: [String: [ContextThreadLinkChip]] = [:]
        for link in links {
            let label = link.label ?? link.rel
            map[link.from, default: []].append(
                ContextThreadLinkChip(rel: link.rel, label: label, peerID: link.to)
            )
            map[link.to, default: []].append(
                ContextThreadLinkChip(rel: link.rel, label: label, peerID: link.from)
            )
        }
        return map
    }

    /// Prefer a heading/anchor section when present; otherwise first ~2KB.
    static func vaultExcerpt(_ text: String, anchor: String?, maxChars: Int = 2_000) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let anchor, !anchor.isEmpty else {
            return String(trimmed.prefix(maxChars))
        }
        // Match markdown heading or bare anchor token on its own line.
        let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
        var start: Int?
        for (i, line) in lines.enumerated() {
            let s = String(line)
            if s.contains(anchor) {
                start = i
                break
            }
        }
        guard let start else {
            return String(trimmed.prefix(maxChars))
        }
        var end = lines.count
        for j in (start + 1)..<lines.count {
            let s = String(lines[j])
            if s.hasPrefix("# ") || s.hasPrefix("## ") {
                end = j
                break
            }
        }
        let slice = lines[start..<end].joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(slice.prefix(maxChars))
    }
}

/// Security-scoped Personal vault root reader (path must stay under root).
public struct PersonalVaultFileReader: ProposeSendVaultReading, Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func readVaultFile(relativePath: String) -> String? {
        guard let fileURL = Self.resolvedFileURL(root: rootURL, relativePath: relativePath) else {
            return nil
        }
        return try? String(contentsOf: fileURL, encoding: .utf8)
    }

    /// Returns nil when path escapes root or does not exist.
    public static func resolvedFileURL(root: URL, relativePath: String) -> URL? {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            _ = try SendProposalContext.sanitizeRelativePath(trimmed, field: "vault")
        } catch {
            return nil
        }
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        let rootPath = root.path
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidatePath, isDirectory: &isDir),
              !isDir.boolValue
        else {
            return nil
        }
        return candidate
    }
}
