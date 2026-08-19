import Foundation
import MailStore
import Observation

enum PrototypeMailSource: String, CaseIterable, Identifiable {
    case fixture
    case liveMail

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fixture: "Fixture mail"
        case .liveMail: "Live Mail store"
        }
    }
}

@Observable
final class PrototypeReadSession {
    let access = MailAccessSession()
    var source: PrototypeMailSource = .fixture
    var query = ""
    var selectedPlacement: Placement?
    var items: [IndexedMessage] = []
    var placements: [Placement] = []
    var detail: ReadMessage?
    var lastIngestAt: Date?
    var lastNewCount = 0
    var status = ""
    var handoffNote: String?
    var mailAccessGranted = false

    private var fixtureRoot: URL
    private var databaseURL: URL
    private var index: MailboxIndex?
    private var api: ReadAPI?

    init() {
        let stamp = UUID().uuidString
        fixtureRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-PROTOTYPE-wipe-me-\(stamp)", isDirectory: true)
        databaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-PROTOTYPE-wipe-me-\(stamp).sqlite")
        refreshAccess()
        reloadIndex()
    }

    func refreshAccess() {
        access.refresh()
        mailAccessGranted = access.snapshot.access == .granted
    }

    func setSource(_ source: PrototypeMailSource) {
        self.source = source
        selectedPlacement = nil
        detail = nil
        query = ""
        reloadIndex()
    }

    func ingestAgain() {
        guard let index else { return }
        do {
            let result = try index.ingest()
            lastIngestAt = Date()
            lastNewCount = result.new.count
            status = "Ingested \(result.new.count) new"
            refresh()
        } catch {
            status = "Ingest failed"
        }
    }

    func refresh() {
        guard let api else { return }
        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let page = trimmed.isEmpty
                ? try api.list(limit: 100)
                : try api.search(trimmed, limit: 100)
            placements = try api.listPlacements()
            items = page.items.filter(matchesPlacement)
            if let detail, !items.contains(where: { $0.rowID == detail.rowID }) {
                self.detail = nil
            }
            status = trimmed.isEmpty ? "\(items.count) messages" : "\(items.count) hits for \(trimmed)"
        } catch {
            items = []
            status = "Search failed"
        }
    }

    func select(_ message: IndexedMessage) {
        guard let api else { return }
        do {
            detail = try api.get(
                accountID: message.accountID,
                placement: message.placement,
                id: message.id
            )
            handoffNote = nil
        } catch {
            detail = nil
            status = "Message not available"
        }
    }

    func openInMail() {
        handoffNote = "Apple Mail handoff needs a Message-ID this index does not store yet."
    }

    private func matchesPlacement(_ message: IndexedMessage) -> Bool {
        guard let selectedPlacement else { return true }
        return message.accountID == selectedPlacement.accountID
            && message.placement == selectedPlacement.id
    }

    private func reloadIndex() {
        try? FileManager.default.removeItem(at: databaseURL)
        do {
            let store: MailStore
            switch source {
            case .fixture:
                try? FileManager.default.removeItem(at: fixtureRoot)
                try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
                let mail = fixtureRoot.appendingPathComponent("Mail", isDirectory: true)
                try PrototypeFixture.plant(at: mail)
                store = MailStore(root: mail)
            case .liveMail:
                guard mailAccessGranted else {
                    status = "Grant access to Mail first"
                    source = .fixture
                    return
                }
                let root = MailFolderBookmark.resolvedURL() ?? MailLibraryProbe.defaultMailDirectory
                store = MailStore(root: root)
            }
            let index = try MailboxIndex(store: store, databaseURL: databaseURL)
            let result = try index.ingest()
            self.index = index
            self.api = ReadAPI(index: index)
            lastIngestAt = Date()
            lastNewCount = result.new.count
            refresh()
        } catch {
            index = nil
            api = nil
            items = []
            placements = []
            status = "Index failed"
        }
    }
}

extension IndexedMessage {
    var rowID: String { "\(accountID)/\(placement)/\(id)" }
}

extension ReadMessage {
    var rowID: String { "\(accountID)/\(placement)/\(id)" }
}

extension Placement {
    var rowID: String { "\(accountID)/\(id)" }
}
