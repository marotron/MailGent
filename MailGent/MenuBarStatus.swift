import AppKit
import MailStore
import SwiftUI

struct MenuBarStatus: View {
    @Bindable var session: CompanionSession
    @ObservedObject private var askQueue = AskQueueIndicator.shared
    @State private var needsActionExpanded = false

    private var accessRequestMenu: AccessRequestMenu {
        AccessRequestMenu.project(askQueue.pending)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text("MailGent")
                    .font(.headline)
                Spacer(minLength: 8)
                Button {
                    DetachedWindowHost.shared.claimActivation()
                    let work = { DetachedWindowHost.shared.showChangelog() }
                    DispatchQueue.main.async(execute: work)
                } label: {
                    Text(MailGentAboutInfo.menuBarVersionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
                .help("View changelog")
            }
            .padding(.horizontal, 8)
            .accessibilityElement(children: .combine)

            // Keep relative-time refresh off the action rows — TimelineView rebuilds
            // were cancelling clicks / swapping which row received the mouse-up.
            TimelineView(.periodic(from: .now, by: 15)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    statusRow("Access") {
                        Text(session.mailAccessGranted ? "Granted" : "Denied")
                            .foregroundStyle(session.mailAccessGranted ? .green : .orange)
                    }
                    lastIngestRow(at: context.date)
                    changesRow(at: context.date)
                    sourceRow
                    statusRow("Connected agent") {
                        ConnectedAgentsValue(names: session.agents.pairedAgents.map(\.name))
                    }
                    lastAgentCallRow(at: context.date)
                }
                .padding(.horizontal, 8)
            }

            Divider()
                .padding(.vertical, 2)
                .padding(.horizontal, 8)

            if accessRequestMenu.isVisible {
                accessRequestsSection
                Divider()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)
            }

            VStack(spacing: 1) {
                MenuBarActionRow(title: "Open Companion", id: "open-companion") {
                    session.openHome()
                    DetachedWindowHost.shared.showCompanion(session: session)
                }
                MenuBarActionRow(title: "Open Grant Desk", id: "open-grant-desk") {
                    DetachedWindowHost.shared.showGrantDesk(session: session)
                }
                MenuBarActionRow(title: "Open Access Log", id: "open-access-log") {
                    DetachedWindowHost.shared.showAccessLog(session: session)
                }
                MenuBarActionRow(title: "Secret constants…", id: "open-secret-constants") {
                    DetachedWindowHost.shared.showSecretConstants(session: session)
                }

                #if DEBUG
                Divider()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)

                MenuBarActionRow(title: "Debug: Ask layout…", id: "debug-ask-layout") {
                    DetachedWindowHost.shared.showAskLayoutSandbox()
                }
                MenuBarActionRow(title: "Debug: Ask layout (long body)…", id: "debug-ask-layout-long") {
                    DetachedWindowHost.shared.showAskLayoutSandbox(longBody: true)
                }
                #endif

                Divider()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)

                MenuBarActionRow(title: "Settings…", id: "settings") {
                    DetachedWindowHost.shared.showSettings(session: session)
                }

                Divider()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)

                MenuBarActionRow(title: "About MailGent", id: "about") {
                    DetachedWindowHost.shared.showAbout()
                }

                Divider()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)

                MenuBarActionRow(title: "Quit MailGent", id: "quit") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .frame(width: 320)
        .onAppear {
            session.refreshAccess()
            DetachedWindowHost.shared.noteStatusMenuOpened()
        }
        .onDisappear {
            DetachedWindowHost.shared.noteStatusMenuClosed()
        }
    }

    private var accessRequestsSection: some View {
        VStack(alignment: .leading, spacing: 1) {
            Button {
                needsActionExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text("Needs your action")
                    Spacer(minLength: 8)
                    Text("\(accessRequestMenu.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 110 / 255, green: 110 / 255, blue: 115 / 255))
                        .rotationEffect(.degrees(needsActionExpanded ? 90 : 0))
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Needs your action")
            .accessibilityValue(accessRequestMenu.accessibilityPhrase ?? "")

            if needsActionExpanded {
                ForEach(accessRequestMenu.rows, id: \.id) { row in
                    AccessRequestMenuRow(row: row)
                }
            }
        }
    }

    private func statusRow<Content: View>(_ title: String, @ViewBuilder value: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            value()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.callout)
    }

    private func lastIngestRow(at now: Date) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Last ingest")
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            LastIngestValue(copy: CompanionStatusCopy(session: session, now: now))
            Button {
                let work = { session.ingestAgain() }
                DispatchQueue.main.async(execute: work)
            } label: {
                Group {
                    if session.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)
            .help("Update ingest")
            .id("quick-ingest")
        }
        .font(.callout)
    }

    private var sourceRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Source")
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            Text(session.source.title)
                .foregroundStyle(session.source == .fixture ? Color.purple : Color.primary)
                .fontWeight(session.source == .fixture ? .semibold : .regular)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                let work = { session.cycleSource() }
                DispatchQueue.main.async(execute: work)
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy || !session.canCycleSource)
            .help("Switch to \(session.nextSource.title)")
            .id("cycle-source")
        }
        .font(.callout)
    }

    private func changesRow(at now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Changes")
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            IngestChangesValue(
                newCount: session.lastNewCount,
                removedCount: session.lastRemovedCount,
                sinceLine: CompanionStatusCopy(session: session, now: now).changesWindow
            )
            Button {
                DetachedWindowHost.shared.claimActivation()
                let work = {
                    session.openLastNewMessages()
                    DetachedWindowHost.shared.showCompanion(session: session)
                }
                DispatchQueue.main.async(execute: work)
            } label: {
                Image(systemName: "envelope")
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.lastNewMessages.isEmpty)
            .help("Open new messages")
            .id("open-new-messages")
        }
        .font(.callout)
    }

    private func lastAgentCallRow(at now: Date) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Last agent call")
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            LastAgentCallValue(copy: CompanionStatusCopy(session: session, now: now))
            Button {
                DetachedWindowHost.shared.claimActivation()
                let work = {
                    DetachedWindowHost.shared.showAccessLog(
                        session: session,
                        selectedID: session.agents.lastAgentRequest?.id
                    )
                }
                DispatchQueue.main.async(execute: work)
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(session.agents.lastAgentRequest == nil)
            .help("Open access log")
            .id("open-last-agent-request")
        }
        .font(.callout)
    }
}

private struct AccessRequestMenuRow: View {
    let row: AccessRequestMenu.Row
    @State private var hovering = false

    private static let markGrey = Color(red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    private static let blockFill = Color(red: 248 / 255, green: 208 / 255, blue: 208 / 255)
    private static let blockInk = Color(red: 196 / 255, green: 18 / 255, blue: 18 / 255)
    private static let allowFill = Color(red: 223 / 255, green: 244 / 255, blue: 228 / 255)
    private static let allowInk = Color(red: 22 / 255, green: 106 / 255, blue: 45 / 255)

    var body: some View {
        HStack(spacing: 4) {
            Button {
                let id = row.id
                DispatchQueue.main.async {
                    DetachedWindowHost.shared.raisePendingAsk(id: id)
                }
            } label: {
                HStack(spacing: 7) {
                    AccessRequestMark(selected: row.isSelected, grey: Self.markGrey)
                    Text(row.label)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering ? Color.black.opacity(0.08) : Color.clear)
            }
            .onHover { hovering = $0 }
            .accessibilityLabel(row.label)
            .accessibilityAddTraits(row.isSelected ? .isSelected : [])

            if row.kind == .ask {
                quickButton("Block", fill: Self.blockFill, ink: Self.blockInk) {
                    let id = row.id
                    DispatchQueue.main.async {
                        DetachedWindowHost.shared.decidePendingAsk(id: id, decision: .block)
                    }
                }
                quickButton("Allow", fill: Self.allowFill, ink: Self.allowInk) {
                    let id = row.id
                    DispatchQueue.main.async {
                        DetachedWindowHost.shared.decidePendingAsk(id: id, decision: .allow)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
        .font(.callout)
    }

    private func quickButton(
        _ title: String,
        fill: Color,
        ink: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill))
        }
        .buttonStyle(.plain)
    }
}

/// Selected mark is a grey disc with the question mark punched out. Unselected is an outline.
private struct AccessRequestMark: View {
    let selected: Bool
    let grey: Color

    var body: some View {
        ZStack {
            if selected {
                Circle().fill(grey)
                Text("?")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.black)
                    .blendMode(.destinationOut)
            } else {
                Circle().strokeBorder(grey, lineWidth: 1)
                Text("?")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(grey)
            }
        }
        .compositingGroup()
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}

/// Menu-item row: full-width, blue hover fill, white label — matches system status menus.
private struct MenuBarActionRow: View {
    let title: String
    let id: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button {
            // Become `.regular` on the click so extra dismiss does not hide the app.
            DetachedWindowHost.shared.claimActivation()
            // Capture work immediately; MenuBarExtra may tear this view down before
            // a synchronous present finishes.
            let work = action
            DispatchQueue.main.async(execute: work)
        } label: {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(id)
        .foregroundStyle(hovering ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .background {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovering ? Color.accentColor : Color.clear)
        }
        .onHover { hovering = $0 }
    }
}
