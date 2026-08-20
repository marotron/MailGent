import Foundation
import OSLog

enum MailGentLog {
    static let index = Logger(subsystem: "app.mailgent.MailGent", category: "index")
    static let store = Logger(subsystem: "app.mailgent.MailGent", category: "store")

    static var verbose: Bool {
        ProcessInfo.processInfo.environment["MAILGENT_VERBOSE"] == "1"
    }

    /// Always mirrors to stderr so Xcode's debug console and `log stream` show output.
    static func trace(_ message: String) {
        let line = "[MailGent] \(message)"
        index.info("\(message, privacy: .public)")
        fputs(line + "\n", stderr)
        fflush(stderr)
        NSLog("%@", line)
    }
}
