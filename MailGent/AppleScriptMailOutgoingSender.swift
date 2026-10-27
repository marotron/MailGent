import AppKit
import Foundation
import MailStore

/// Runs `MailOutgoingAppleScript` via `NSAppleScript` into Apple Mail.
final class AppleScriptMailOutgoingSender: MailOutgoingSending, @unchecked Sendable {
    func deliver(_ proposal: SendProposal, mode: MailOutgoingMode) throws {
        let source = MailOutgoingAppleScript.script(for: proposal, mode: mode)
        try run(source: source)
    }

    private func run(source: String) throws {
        if Thread.isMainThread {
            try execute(source: source)
        } else {
            var caught: Error?
            DispatchQueue.main.sync {
                do {
                    try execute(source: source)
                } catch {
                    caught = error
                }
            }
            if let caught { throw caught }
        }
    }

    private func execute(source: String) throws {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else {
            throw MailOutgoingError.scriptFailed("Could not compile AppleScript for Mail.")
        }
        _ = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw MailOutgoingError.scriptFailed(message ?? "Apple Mail scripting failed.")
        }
    }
}
