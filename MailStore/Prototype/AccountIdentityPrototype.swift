// PROTOTYPE — answers: can MailGent resolve account UUID → name + email?
// Run: make prototype-accounts
// Live `~/Library/Mail` needs Full Disk Access on *this* process (not MailGent.app).
// Cursor's terminal usually has none — Choose Mail folder (Open Panel) is the fallback.
import AppKit
import Darwin
import Foundation
import MailStore
import SQLite3

private enum Ansi {
    static let bold = "\u{001B}[1m"
    static let dim = "\u{001B}[2m"
    static let reset = "\u{001B}[0m"
}

@main
struct AccountIdentityPrototype {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)

        var state = PrototypeState()
        if CommandLine.arguments.dropFirst().first != nil {
            let path = CommandLine.arguments[1]
            state.useExplicitRoot(URL(fileURLWithPath: path, isDirectory: true))
        } else {
            state.boot()
        }
        render(state)

        while true {
            print("\n\(Ansi.bold)Keys\(Ansi.reset)  \(Ansi.dim)[o] choose Mail folder  [l] live  [f] fixture  [r] refresh  [s] sources  [q] quit\(Ansi.reset)")
            guard let line = readLine(strippingNewline: true)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  let key = line.first?.lowercased()
            else { continue }

            switch key {
            case "q":
                return
            case "r":
                state.reload()
            case "s":
                state.showSources.toggle()
            case "o":
                state.chooseMailFolder()
            case "l":
                state.useLive()
            case "f":
                state.useFixture()
            default:
                continue
            }
            render(state)
        }
    }

    private static func render(_ state: PrototypeState) {
        print("\u{001B}[2J\u{001B}[H")
        print("\(Ansi.bold)MailGent account identity prototype\(Ansi.reset)")
        print("\(Ansi.dim)mode: \(state.modeLabel)\(Ansi.reset)")
        print("\(Ansi.dim)Mail root: \(state.mailRoot.path)\(Ansi.reset)")
        if let note = state.note {
            print("\n\(note)")
        }
        if let error = state.error {
            print("\n\(Ansi.bold)error\(Ansi.reset)  \(error)")
            return
        }
        print("\n\(Ansi.bold)accounts\(Ansi.reset)  \(state.identities.count)")
        for identity in state.identities {
            print("")
            print("  \(Ansi.bold)\(identity.displayName)\(Ansi.reset)")
            if let email = identity.email, email != identity.displayName {
                print("  \(Ansi.dim)email\(Ansi.reset)     \(email)")
            } else if let email = identity.email,
                      let brand = MailAccountIdentityResolver.displayName(fromEmail: email)
            {
                print("  \(Ansi.dim)provider\(Ansi.reset)  \(brand)")
            } else if identity.email == nil {
                print("  \(Ansi.dim)email\(Ansi.reset)     —")
            }
            print("  \(Ansi.dim)uuid\(Ansi.reset)      \(identity.id)")
            if state.showSources {
                print("  \(Ansi.dim)source\(Ansi.reset)    \(identity.source.rawValue)")
            }
        }
    }
}

private struct PrototypeState {
    var mailRoot: URL
    var accountsDatabases: [URL]?
    var identities: [MailAccountIdentity] = []
    var error: String?
    var note: String?
    var showSources = true
    var mode: Mode = .live

    enum Mode {
        case live
        case picked
        case fixture
        case explicit
    }

    var modeLabel: String {
        switch mode {
        case .live: "live ~/Library/Mail"
        case .picked: "Open Panel (user-selected Mail folder)"
        case .fixture: "fixture (PROTOTYPE — wipe me)"
        case .explicit: "argv path"
        }
    }

    init() {
        mailRoot = MailAccountIdentityResolver.defaultMailLibraryURL
    }

    mutating func boot() {
        useLive()
        if error != nil {
            if isatty(STDIN_FILENO) != 0 {
                note = "Live Mail unreadable from this terminal (no Full Disk Access on Cursor/this CLI). MailGent.app can still read it. Opening folder picker…"
                chooseMailFolder()
                if error != nil {
                    note = "Picker cancelled. Showing fixture so you can still see Accounts4.sqlite vs header inference vs UUID fallback."
                    useFixture()
                }
            } else {
                note = "Live Mail unreadable (no TTY for Open Panel). Showing fixture."
                useFixture()
            }
        }
    }

    mutating func useExplicitRoot(_ url: URL) {
        mode = .explicit
        mailRoot = url
        accountsDatabases = nil
        note = nil
        reload()
    }

    mutating func useLive() {
        mode = .live
        mailRoot = MailAccountIdentityResolver.defaultMailLibraryURL
        accountsDatabases = nil
        note = nil
        reload()
        if error != nil {
            note = "This CLI is not MailGent.app. Grant Full Disk Access to Terminal (or Cursor), or press [o] and pick ~/Library/Mail."
        }
    }

    mutating func useFixture() {
        do {
            let planted = try PrototypeFixture.plant()
            mode = .fixture
            mailRoot = planted.mailRoot
            accountsDatabases = [planted.accountsDB]
            note = "Fixture: DB description, inferred email, UUID fallback. Live Mail usually infers — Accounts4.sqlite is a different TCC path."
            error = nil
            reload()
        } catch {
            identities = []
            self.error = String(describing: error)
        }
    }

    mutating func chooseMailFolder() {
        guard let url = OpenMailPanel.run() else {
            note = "Folder picker cancelled."
            return
        }
        mode = .picked
        mailRoot = url
        accountsDatabases = nil
        note = "Using user-selected folder (TCC exception — same path as MailGent’s Choose Mail Folder)."
        reload()
    }

    mutating func reload() {
        error = nil
        do {
            let store = MailStore(root: mailRoot)
            identities = try MailAccountIdentityResolver.resolve(
                in: store,
                accountsDatabases: accountsDatabases
            )
        } catch {
            identities = []
            self.error = explain(error)
        }
    }

    private func explain(_ error: Error) -> String {
        if let storeError = error as? MailStoreError {
            switch storeError {
            case .unreadable:
                return "unreadable — cannot list \(mailRoot.path) (TCC). Press [o] to choose the folder, [f] for fixture."
            case .mailLibraryNotFound:
                return "mail library not found at \(mailRoot.path)"
            case .noVersionFolder:
                return "no V* folder under \(mailRoot.path)"
            default:
                return String(describing: storeError)
            }
        }
        return String(describing: error)
    }
}

private enum OpenMailPanel {
    static func run() -> URL? {
        let app = NSApplication.shared
        app.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.message = "Choose Apple Mail’s library folder (usually ~/Library/Mail)."
        panel.prompt = "Choose Mail folder"
        panel.directoryURL = MailAccountIdentityResolver.defaultMailLibraryURL
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}

/// Throwaway on-disk tree. Not the production fixture.
private enum PrototypeFixture {
    struct Planted {
        let mailRoot: URL
        let accountsDB: URL
    }

    static let dbAccount = "11111111-1111-1111-1111-111111111111"
    static let inferredAccount = "22222222-2222-2222-2222-222222222222"
    static let fallbackAccount = "33333333-3333-3333-3333-333333333333"

    static func plant() throws -> Planted {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MailGent-identity-proto-\(UUID().uuidString)", isDirectory: true)
        let mail = root.appendingPathComponent("Mail", isDirectory: true)
        try FileManager.default.createDirectory(at: mail, withIntermediateDirectories: true)
        try writeMailbox(mail: mail, account: dbAccount, mailbox: "INBOX")
        try writeMailbox(mail: mail, account: inferredAccount, mailbox: "Sent Messages")
        try writeMailbox(mail: mail, account: fallbackAccount, mailbox: "INBOX")
        try writeEmlx(
            mail: mail,
            account: inferredAccount,
            mailbox: "Sent Messages",
            name: "1.emlx",
            rfc822: """
            From: Marek <alice@example.com>
            To: team@example.com
            Subject: shipping notes
            Date: Thu, 20 Aug 2026 09:00:00 +0100

            Sent from this account.
            """
        )
        let db = root.appendingPathComponent("Accounts4.sqlite")
        try writeAccountsDB(at: db)
        return Planted(mailRoot: mail, accountsDB: db)
    }

    private static func writeMailbox(mail: URL, account: String, mailbox: String) throws {
        let mbox = mail
            .appendingPathComponent("V10", isDirectory: true)
            .appendingPathComponent(account, isDirectory: true)
            .appendingPathComponent("\(mailbox).mbox", isDirectory: true)
        try FileManager.default.createDirectory(at: mbox, withIntermediateDirectories: true)
        try Data("placeholder".utf8).write(to: mbox.appendingPathComponent("table_of_contents"))
    }

    private static func writeEmlx(mail: URL, account: String, mailbox: String, name: String, rfc822: String) throws {
        let messages = mail
            .appendingPathComponent("V10", isDirectory: true)
            .appendingPathComponent(account, isDirectory: true)
            .appendingPathComponent("\(mailbox).mbox", isDirectory: true)
            .appendingPathComponent("Messages", isDirectory: true)
        try FileManager.default.createDirectory(at: messages, withIntermediateDirectories: true)
        let payload = Data(rfc822.utf8)
        var file = Data()
        file.append(Data("\(payload.count)\n".utf8))
        file.append(payload)
        try file.write(to: messages.appendingPathComponent(name))
    }

    private static func writeAccountsDB(at url: URL) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw PrototypeFixtureError.sqlite
        }
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE ZACCOUNT (ZIDENTIFIER TEXT, ZACCOUNTDESCRIPTION TEXT, ZUSERNAME TEXT);
        INSERT INTO ZACCOUNT VALUES ('\(dbAccount)', 'Work Gmail', 'you@company.com');
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw PrototypeFixtureError.sqlite
        }
    }
}

private enum PrototypeFixtureError: Error {
    case sqlite
}
