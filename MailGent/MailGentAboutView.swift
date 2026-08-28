import AppKit
import SwiftUI

enum MailGentAboutInfo {
    static var marketingVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var versionLine: String {
        "Version \(marketingVersion) (\(buildNumber))"
    }

    static let tagline = "macOS menu-bar companion beside Apple Mail."
    static let summary =
        "Not a daily client. No built-in AI. External agents talk to MailGent over MCP on your machine."

    static func changelogText() -> String {
        guard
            let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
            let raw = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "# Changelog\n\nChangelog file is not bundled in this build."
        }
        if let range = raw.range(of: "\n## [") {
            return String(raw[range.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ChangelogRelease: Identifiable {
    var id: String { version }
    let version: String
    let date: String
    let sections: [ChangelogSection]
}

private struct ChangelogSection: Identifiable {
    var id: String { title }
    let title: String
    let items: [String]
}

private enum ChangelogParser {
    static func parseReleases(from raw: String) -> [ChangelogRelease] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("## [") else { return [] }

        let blocks = trimmed.components(separatedBy: "## [")
        var releases: [ChangelogRelease] = []

        for block in blocks.dropFirst() {
            guard
                let headerEnd = block.firstIndex(of: "]"),
                let release = parseReleaseBlock(String(block[..<headerEnd]), body: String(block[block.index(after: headerEnd)...]))
            else { continue }
            releases.append(release)
        }

        return releases
    }

    private static func parseReleaseBlock(_ version: String, body: String) -> ChangelogRelease? {
        let trimmedVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedVersion.isEmpty else { return nil }

        let lines = body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let dateLine = lines.first else { return nil }

        let date = dateLine
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        guard !date.isEmpty else { return nil }

        let remainder = lines.dropFirst().joined(separator: "\n")
        return ChangelogRelease(
            version: trimmedVersion,
            date: date,
            sections: parseSections(from: remainder)
        )
    }

    private static func parseSections(from body: String) -> [ChangelogSection] {
        body
            .components(separatedBy: "\n### ")
            .dropFirst()
            .compactMap { block in
                let lines = block.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                guard let title = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
                    return nil
                }
                let items = lines.dropFirst()
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.hasPrefix("- ") }
                    .map { String($0.dropFirst(2)) }
                guard !items.isEmpty else { return nil }
                return ChangelogSection(title: title, items: items)
            }
    }
}

struct MailGentAboutView: View {
    var body: some View {
        VStack(spacing: 16) {
            if let icon = NSApplication.shared.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 96, height: 96)
            }

            VStack(spacing: 4) {
                Text("MailGent")
                    .font(.title.bold())
                Text(MailGentAboutInfo.versionLine)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                Text(MailGentAboutInfo.tagline)
                Text(MailGentAboutInfo.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 340)

            VStack(spacing: 4) {
                aboutBullet("Apple Mail local-read with on-device SQLite search")
                aboutBullet("Loopback MCP, grants, access log, draft ledger")
                aboutBullet("Device-first — data stays on this Mac")
            }
            .font(.callout)
            .frame(maxWidth: 340)

            Button("View changelog…") {
                DetachedWindowHost.shared.showChangelog()
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Text("Copyright © 2026. Licensed under Apache-2.0.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(28)
        .frame(width: 400)
    }

    private func aboutBullet(_ text: String) -> some View {
        Text("• \(text)")
            .frame(maxWidth: .infinity)
    }
}

struct MailGentChangelogView: View {
    private let releases = ChangelogParser.parseReleases(from: MailGentAboutInfo.changelogText())

    var body: some View {
        ScrollView {
            if releases.isEmpty {
                Text(MailGentAboutInfo.changelogText())
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            } else {
                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(releases) { release in
                        releaseSection(release)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 480, minHeight: 420)
    }

    @ViewBuilder
    private func releaseSection(_ release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(release.version) — \(release.date)")
                .font(.headline)

            ForEach(release.sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)

                    ForEach(Array(section.items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(.secondary)
                            changelogItemText(item)
                                .font(.callout)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func changelogItemText(_ item: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: item,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(item)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
