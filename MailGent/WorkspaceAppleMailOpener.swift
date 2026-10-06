import AppKit
import MailStore

/// AppKit adapter: opens `message://` via `NSWorkspace` (MailStore stays Foundation-only).
final class WorkspaceAppleMailOpener: AppleMailOpening, @unchecked Sendable {
    func openMessage(internetMessageID: String) -> Bool {
        guard let url = AppleMailHandoff.messageURL(internetMessageID: internetMessageID) else {
            return false
        }
        if Thread.isMainThread {
            return NSWorkspace.shared.open(url)
        }
        var opened = false
        DispatchQueue.main.sync {
            opened = NSWorkspace.shared.open(url)
        }
        return opened
    }
}
