import AppKit
import MailStore
import SwiftUI

struct MenuBarStatus: View {
    @Bindable var session: CompanionSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center) {
                Text("MailGent")
                    .font(.headline)
                Spacer(minLength: 8)
                Text(marketingVersionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
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
                    changesRow
                    sourceRow
                    statusRow("Connected agent") {
                        Text(session.agents.agent?.name ?? "—")
                    }
                    lastAgentRequestRow(at: context.date)
                }
                .padding(.horizontal, 8)
            }

            Divider()
                .padding(.vertical, 2)
                .padding(.horizontal, 8)

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

                Divider()
                    .padding(.vertical, 2)
                    .padding(.horizontal, 8)

                MenuBarActionRow(title: "Settings…", id: "settings") {
                    DetachedWindowHost.shared.showSettings(session: session)
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
        .onAppear(perform: session.refreshAccess)
    }

    private var marketingVersionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let version, !version.isEmpty else { return "—" }
        return "v\(version)"
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

    private var changesRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Changes")
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            IngestChangesValue(
                newCount: session.lastNewCount,
                removedCount: session.lastRemovedCount,
                sinceLine: CompanionStatusCopy(session: session, now: .now).changesSince
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

    private func lastAgentRequestRow(at now: Date) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Last agent request")
                .foregroundStyle(.secondary)
                .frame(width: 118, alignment: .leading)
            Text(CompanionStatusCopy(session: session, now: now).lastAgentRequest)
                .frame(maxWidth: .infinity, alignment: .leading)
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
