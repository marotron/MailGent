import AppKit
import Foundation
import Observation

/// PROTOTYPE — in-memory draft outbound session. Wipe with the process.
@MainActor
@Observable
final class PrototypeDraftSession {
    struct SourceMessage: Equatable, Identifiable {
        let id: String
        let accountLabel: String
        let placement: String
        let from: String
        let subject: String
        let body: String
    }

    struct LedgerVersion: Equatable, Identifiable {
        let id: String
        let label: String
        let body: String
        let savedAt: Date
    }

    let source = SourceMessage(
        id: "1",
        accountLabel: "Work Gmail",
        placement: "INBOX",
        from: "Ava Chen <ava@company.com>",
        subject: "Q3 planning notes",
        body: "Here is the revised schedule and proposed next steps for quarterly planning."
    )

    /// Shared composer text (both variants edit this).
    var draftText = """
    Hi Ava —

    Thanks for the schedule. I can take the Thursday planning slot and will send a short agenda by end of day.

    — You
    """

    /// A-only: last clipboard outcome.
    var lastCopiedAt: Date?
    var lastCopiedPreview = ""
    var copyCount = 0

    /// B-only: versioned ledger (still no Mail-store write).
    var versions: [LedgerVersion] = []
    var selectedVersionID: String?
    var lastLedgerAction = "none"

    /// Shared: dump for the state surface after every action.
    var lastAction = "launched"
    var lastActionAt = Date()

    var selectedVersion: LedgerVersion? {
        versions.first { $0.id == selectedVersionID }
    }

    func note(_ action: String) {
        lastAction = action
        lastActionAt = Date()
    }

    func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(draftText, forType: .string)
        lastCopiedAt = Date()
        lastCopiedPreview = draftText
        copyCount += 1
        note("copied \(draftText.count) chars to clipboard")
    }

    func saveLedgerVersion() {
        let n = versions.count + 1
        let version = LedgerVersion(
            id: UUID().uuidString,
            label: "v\(n)",
            body: draftText,
            savedAt: Date()
        )
        versions.insert(version, at: 0)
        selectedVersionID = version.id
        lastLedgerAction = "saved \(version.label)"
        note("ledger saved \(version.label) (\(version.body.count) chars)")
    }

    func selectVersion(_ id: String) {
        guard let version = versions.first(where: { $0.id == id }) else { return }
        selectedVersionID = id
        draftText = version.body
        lastLedgerAction = "loaded \(version.label)"
        note("ledger loaded \(version.label)")
    }

    func copyCurrentLedgerVersion() {
        let body = selectedVersion?.body ?? draftText
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(body, forType: .string)
        lastCopiedAt = Date()
        lastCopiedPreview = body
        copyCount += 1
        lastLedgerAction = "copied current"
        note("ledger copied current (\(body.count) chars)")
    }

    func openMailApp() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mail.app"))
        note("opened Mail.app (paste manually)")
    }

    var stateDump: String {
        """
        lastAction: \(lastAction)
        at: \(lastActionAt.formatted(date: .omitted, time: .standard))
        draftChars: \(draftText.count)
        copyCount: \(copyCount)
        lastCopiedAt: \(lastCopiedAt?.formatted(date: .omitted, time: .standard) ?? "—")
        lastCopiedPreview: \(preview(lastCopiedPreview))
        ledgerVersions: \(versions.count)
        selectedVersion: \(selectedVersion?.label ?? "—")
        lastLedgerAction: \(lastLedgerAction)
        source: \(source.accountLabel)/\(source.placement) · \(source.subject)
        """
    }

    private func preview(_ text: String) -> String {
        let oneLine = text.replacingOccurrences(of: "\n", with: "↵")
        if oneLine.count <= 80 { return oneLine.isEmpty ? "—" : oneLine }
        return String(oneLine.prefix(77)) + "…"
    }
}
