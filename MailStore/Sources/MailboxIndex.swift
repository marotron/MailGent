import Foundation
import SQLite3

/// On-device cache of a Mail tree. Ingest is the on-open sweep; FSEvents is a later caller.
public final class MailboxIndex {
    public let store: MailStore
    public let databaseURL: URL
    private let db: SQLiteDB

    public init(store: MailStore, databaseURL: URL) throws {
        self.store = store
        self.databaseURL = databaseURL
        self.db = try SQLiteDB(url: databaseURL)
        try db.execute("""
            CREATE TABLE IF NOT EXISTS messages (
                account_id TEXT NOT NULL,
                placement TEXT NOT NULL,
                message_id TEXT NOT NULL,
                from_addr TEXT NOT NULL,
                to_addr TEXT NOT NULL,
                date TEXT NOT NULL,
                subject TEXT NOT NULL,
                body TEXT NOT NULL,
                is_partial INTEGER NOT NULL,
                path TEXT NOT NULL,
                inode INTEGER NOT NULL,
                mtime REAL NOT NULL,
                size INTEGER NOT NULL,
                PRIMARY KEY (account_id, placement, message_id)
            )
            """)
        try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
                from_addr, to_addr, date, subject, body,
                content='messages',
                content_rowid='rowid'
            )
            """)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS messages_ai AFTER INSERT ON messages BEGIN
                INSERT INTO messages_fts(rowid, from_addr, to_addr, date, subject, body)
                VALUES (new.rowid, new.from_addr, new.to_addr, new.date, new.subject, new.body);
            END
            """)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS messages_ad AFTER DELETE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, rowid, from_addr, to_addr, date, subject, body)
                VALUES('delete', old.rowid, old.from_addr, old.to_addr, old.date, old.subject, old.body);
            END
            """)
        try db.execute("""
            CREATE TRIGGER IF NOT EXISTS messages_au AFTER UPDATE ON messages BEGIN
                INSERT INTO messages_fts(messages_fts, rowid, from_addr, to_addr, date, subject, body)
                VALUES('delete', old.rowid, old.from_addr, old.to_addr, old.date, old.subject, old.body);
                INSERT INTO messages_fts(rowid, from_addr, to_addr, date, subject, body)
                VALUES (new.rowid, new.from_addr, new.to_addr, new.date, new.subject, new.body);
            END
            """)
    }

    public func ingest(
        totalHint: Int? = nil,
        onProgress: (@Sendable (IngestProgress) -> Void)? = nil
    ) throws -> IngestResult {
        var new: [IndexedMessageRef] = []
        var processed = 0
        var lastReportedAccount = ""
        var lastReportedMailbox = ""
        for account in try store.accounts() {
            try Task.checkCancellation()
            for mailbox in try store.mailboxes(in: account.id) {
                try Task.checkCancellation()
                let directory = try store.mailboxURL(accountID: account.id, mailboxID: mailbox.id)
                func report() {
                    reportProgress(
                        onProgress,
                        processed: processed,
                        inserted: new.count,
                        accountID: account.id,
                        mailboxID: mailbox.id,
                        totalHint: totalHint,
                        lastAccount: &lastReportedAccount,
                        lastMailbox: &lastReportedMailbox
                    )
                }
                try MailStore.forEachEmlxEntry(under: directory) { entry in
                    try autoreleasepool {
                        processed += 1
                        let id = entry.id
                        let url = entry.url
                        let identity: FileIdentity
                        do {
                            identity = try FileIdentity(url: url)
                        } catch {
                            report()
                            return
                        }
                        if try storedIdentity(accountID: account.id, placement: mailbox.id, id: id) == identity {
                            report()
                            return
                        }
                        let message: MailMessage
                        do {
                            message = try store.message(at: url)
                        } catch {
                            report()
                            return
                        }
                        try upsert(accountID: account.id, placement: mailbox.id, id: id, message: message, identity: identity)
                        new.append(IndexedMessageRef(accountID: account.id, placement: mailbox.id, id: id))
                        report()
                    }
                }
            }
        }
        new.sort {
            ($0.accountID, $0.placement, $0.id) < ($1.accountID, $1.placement, $1.id)
        }
        return IngestResult(new: new)
    }

    private func reportProgress(
        _ onProgress: (@Sendable (IngestProgress) -> Void)?,
        processed: Int,
        inserted: Int,
        accountID: String,
        mailboxID: String,
        totalHint: Int?,
        lastAccount: inout String,
        lastMailbox: inout String
    ) {
        guard let onProgress else { return }
        let mailboxChanged = accountID != lastAccount || mailboxID != lastMailbox
        guard processed == 1 || processed % 25 == 0 || mailboxChanged else { return }
        lastAccount = accountID
        lastMailbox = mailboxID
        onProgress(
            IngestProgress(
                processed: processed,
                inserted: inserted,
                accountID: accountID,
                mailboxID: mailboxID,
                phase: .indexing,
                totalHint: totalHint
            )
        )
    }

    public func ingest() throws -> IngestResult {
        try ingest(onProgress: nil)
    }

    public func search(_ query: String) throws -> [IndexedMessage] {
        var hits: [IndexedMessage] = []
        try db.query(
            """
            SELECT m.account_id, m.placement, m.message_id, m.from_addr, m.to_addr, m.date, m.subject, m.body, m.is_partial
            FROM messages_fts
            JOIN messages m ON m.rowid = messages_fts.rowid
            WHERE messages_fts MATCH ?
            ORDER BY m.account_id, m.placement, m.message_id
            """,
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, query, -1, SQLITE_TRANSIENT)
            },
            row: { stmt in
                hits.append(indexedMessage(from: stmt))
            }
        )
        return hits
    }

    func allMessages() throws -> [IndexedMessage] {
        var rows: [IndexedMessage] = []
        try db.query(
            """
            SELECT account_id, placement, message_id, from_addr, to_addr, date, subject, body, is_partial
            FROM messages
            ORDER BY account_id, placement, message_id
            """,
            row: { stmt in
                rows.append(indexedMessage(from: stmt))
            }
        )
        return rows
    }

    func messageCount() throws -> Int {
        var count = 0
        try db.query(
            "SELECT COUNT(*) FROM messages",
            row: { stmt in
                count = Int(sqlite3_column_int64(stmt, 0))
            }
        )
        return count
    }

    func distinctPlacements() throws -> [(accountID: String, placement: String)] {
        var rows: [(String, String)] = []
        try db.query(
            """
            SELECT DISTINCT account_id, placement
            FROM messages
            ORDER BY account_id, placement
            """,
            row: { stmt in
                rows.append((sqlite3_column_string(stmt, 0), sqlite3_column_string(stmt, 1)))
            }
        )
        return rows
    }

    func placementIndexedCounts() throws -> [String: Int] {
        var counts: [String: Int] = [:]
        try db.query(
            """
            SELECT account_id, placement, COUNT(*)
            FROM messages
            GROUP BY account_id, placement
            """,
            row: { stmt in
                let key = "\(sqlite3_column_string(stmt, 0))/\(sqlite3_column_string(stmt, 1))"
                counts[key] = Int(sqlite3_column_int64(stmt, 2))
            }
        )
        return counts
    }

    func listMessages(
        limit: Int,
        offset: Int,
        accountID: String? = nil,
        placement: String? = nil
    ) throws -> [IndexedMessage] {
        var rows: [IndexedMessage] = []
        var clauses: [String] = []
        if accountID != nil { clauses.append("account_id = ?") }
        if placement != nil { clauses.append("placement = ?") }
        let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        try db.query(
            """
            SELECT account_id, placement, message_id, from_addr, to_addr, date, subject, is_partial
            FROM messages
            \(whereSQL)
            ORDER BY account_id, placement, message_id
            LIMIT ? OFFSET ?
            """,
            bind: { stmt in
                var index: Int32 = 1
                if let accountID {
                    sqlite3_bind_text(stmt, index, accountID, -1, SQLITE_TRANSIENT)
                    index += 1
                }
                if let placement {
                    sqlite3_bind_text(stmt, index, placement, -1, SQLITE_TRANSIENT)
                    index += 1
                }
                sqlite3_bind_int(stmt, index, Int32(limit))
                sqlite3_bind_int(stmt, index + 1, Int32(offset))
            },
            row: { stmt in
                rows.append(indexedMessageSummary(from: stmt))
            }
        )
        return rows
    }

    func searchMessages(
        _ query: String,
        limit: Int,
        offset: Int,
        accountID: String? = nil,
        placement: String? = nil
    ) throws -> [IndexedMessage] {
        var hits: [IndexedMessage] = []
        var clauses = ["messages_fts MATCH ?"]
        if accountID != nil { clauses.append("m.account_id = ?") }
        if placement != nil { clauses.append("m.placement = ?") }
        try db.query(
            """
            SELECT m.account_id, m.placement, m.message_id, m.from_addr, m.to_addr, m.date, m.subject, m.is_partial
            FROM messages_fts
            JOIN messages m ON m.rowid = messages_fts.rowid
            WHERE \(clauses.joined(separator: " AND "))
            ORDER BY m.account_id, m.placement, m.message_id
            LIMIT ? OFFSET ?
            """,
            bind: { stmt in
                var index: Int32 = 1
                sqlite3_bind_text(stmt, index, query, -1, SQLITE_TRANSIENT)
                index += 1
                if let accountID {
                    sqlite3_bind_text(stmt, index, accountID, -1, SQLITE_TRANSIENT)
                    index += 1
                }
                if let placement {
                    sqlite3_bind_text(stmt, index, placement, -1, SQLITE_TRANSIENT)
                    index += 1
                }
                sqlite3_bind_int(stmt, index, Int32(limit))
                sqlite3_bind_int(stmt, index + 1, Int32(offset))
            },
            row: { stmt in
                hits.append(indexedMessageSummary(from: stmt))
            }
        )
        return hits
    }

    public func get(accountID: String, placement: String, id: String) throws -> IndexedMessage {
        var found: IndexedMessage?
        try db.query(
            """
            SELECT account_id, placement, message_id, from_addr, to_addr, date, subject, body, is_partial
            FROM messages
            WHERE account_id = ? AND placement = ? AND message_id = ?
            """,
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, accountID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, placement, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
            },
            row: { stmt in
                found = indexedMessage(from: stmt)
            }
        )
        guard let found else { throw MailboxIndexError.messageNotFound }
        return found
    }

    private func indexedMessage(from stmt: OpaquePointer) -> IndexedMessage {
        IndexedMessage(
            id: sqlite3_column_string(stmt, 2),
            accountID: sqlite3_column_string(stmt, 0),
            placement: sqlite3_column_string(stmt, 1),
            from: sqlite3_column_string(stmt, 3),
            to: sqlite3_column_string(stmt, 4),
            date: sqlite3_column_string(stmt, 5),
            subject: sqlite3_column_string(stmt, 6),
            body: sqlite3_column_string(stmt, 7),
            isPartial: sqlite3_column_int(stmt, 8) != 0
        )
    }

    private func indexedMessageSummary(from stmt: OpaquePointer) -> IndexedMessage {
        IndexedMessage(
            id: sqlite3_column_string(stmt, 2),
            accountID: sqlite3_column_string(stmt, 0),
            placement: sqlite3_column_string(stmt, 1),
            from: sqlite3_column_string(stmt, 3),
            to: sqlite3_column_string(stmt, 4),
            date: sqlite3_column_string(stmt, 5),
            subject: sqlite3_column_string(stmt, 6),
            body: "",
            isPartial: sqlite3_column_int(stmt, 7) != 0
        )
    }

    private func storedIdentity(accountID: String, placement: String, id: String) throws -> FileIdentity? {
        var found: FileIdentity?
        try db.query(
            """
            SELECT path, inode, mtime, size FROM messages
            WHERE account_id = ? AND placement = ? AND message_id = ?
            """,
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, accountID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, placement, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
            },
            row: { stmt in
                found = FileIdentity(
                    path: sqlite3_column_string(stmt, 0),
                    inode: UInt64(sqlite3_column_int64(stmt, 1)),
                    mtime: sqlite3_column_double(stmt, 2),
                    size: Int(sqlite3_column_int64(stmt, 3))
                )
            }
        )
        return found
    }

    private func upsert(
        accountID: String,
        placement: String,
        id: String,
        message: MailMessage,
        identity: FileIdentity
    ) throws {
        try db.execute(
            """
            INSERT INTO messages (
                account_id, placement, message_id, from_addr, to_addr, date, subject, body, is_partial,
                path, inode, mtime, size
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_id, placement, message_id) DO UPDATE SET
                from_addr = excluded.from_addr,
                to_addr = excluded.to_addr,
                date = excluded.date,
                subject = excluded.subject,
                body = excluded.body,
                is_partial = excluded.is_partial,
                path = excluded.path,
                inode = excluded.inode,
                mtime = excluded.mtime,
                size = excluded.size
            """,
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, accountID, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 2, placement, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 4, message.from, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 5, message.to, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 6, message.date, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 7, message.subject, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(stmt, 8, message.body, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 9, message.isPartial ? 1 : 0)
                sqlite3_bind_text(stmt, 10, identity.path, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int64(stmt, 11, Int64(bitPattern: identity.inode))
                sqlite3_bind_double(stmt, 12, identity.mtime)
                sqlite3_bind_int64(stmt, 13, Int64(identity.size))
            }
        )
    }
}

private struct FileIdentity: Equatable {
    let path: String
    let inode: UInt64
    let mtime: TimeInterval
    let size: Int

    init(path: String, inode: UInt64, mtime: TimeInterval, size: Int) {
        self.path = path
        self.inode = inode
        self.mtime = mtime
        self.size = size
    }

    init(url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw MailboxIndexError.unreadable
        }
        self.path = url.path
        self.inode = info.st_ino
        self.mtime = Double(info.st_mtimespec.tv_sec) + Double(info.st_mtimespec.tv_nsec) / 1_000_000_000
        self.size = Int(info.st_size)
    }
}

public enum IngestPhase: Sendable, Equatable {
    case scanning
    case indexing
}

public struct IngestProgress: Sendable, Equatable {
    public let processed: Int
    public let inserted: Int
    public let accountID: String
    public let mailboxID: String
    public let phase: IngestPhase
    public let totalHint: Int?

    public init(
        processed: Int,
        inserted: Int,
        accountID: String,
        mailboxID: String,
        phase: IngestPhase = .indexing,
        totalHint: Int? = nil
    ) {
        self.processed = processed
        self.inserted = inserted
        self.accountID = accountID
        self.mailboxID = mailboxID
        self.phase = phase
        self.totalHint = totalHint
    }
}

public struct IngestResult: Equatable, Sendable {
    public let new: [IndexedMessageRef]
}

public struct IndexedMessageRef: Equatable, Sendable {
    public let accountID: String
    public let placement: String
    public let id: String

    public init(accountID: String, placement: String, id: String) {
        self.accountID = accountID
        self.placement = placement
        self.id = id
    }
}

public struct IndexedMessage: Equatable, Sendable {
    public let id: String
    public let accountID: String
    public let placement: String
    public let from: String
    public let to: String
    public let date: String
    public let subject: String
    public let body: String
    public let isPartial: Bool
}

public enum MailboxIndexError: Error, Equatable {
    case unreadable
    case messageNotFound
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func sqlite3_column_string(_ stmt: OpaquePointer, _ index: Int32) -> String {
    guard let cString = sqlite3_column_text(stmt, index) else { return "" }
    return String(cString: cString)
}

private final class SQLiteDB {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let status = sqlite3_open_v2(url.path, &handle, flags, nil)
        guard status == SQLITE_OK else {
            sqlite3_close(handle)
            handle = nil
            throw MailboxIndexError.unreadable
        }
    }

    deinit {
        sqlite3_close(handle)
    }

    func execute(_ sql: String, bind: ((OpaquePointer) -> Void)? = nil) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MailboxIndexError.unreadable
        }
        defer { sqlite3_finalize(stmt) }
        bind?(stmt)
        let step = sqlite3_step(stmt)
        guard step == SQLITE_DONE || step == SQLITE_ROW else {
            throw MailboxIndexError.unreadable
        }
    }

    func query(
        _ sql: String,
        bind: ((OpaquePointer) -> Void)? = nil,
        row: (OpaquePointer) -> Void
    ) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw MailboxIndexError.unreadable
        }
        defer { sqlite3_finalize(stmt) }
        bind?(stmt)
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                row(stmt)
            } else if step == SQLITE_DONE {
                break
            } else {
                throw MailboxIndexError.unreadable
            }
        }
    }
}
