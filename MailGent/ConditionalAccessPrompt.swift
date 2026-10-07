import Foundation
import MailStore
import SwiftUI

/// Request to prompt user for conditional field access.
public struct ConditionalAccessPromptRequest: Identifiable, Sendable {
    public let id: String
    public let agentName: String
    public let accountID: String
    public let placement: String
    public let requestedFields: [String]
    
    public init(
        id: String = UUID().uuidString,
        agentName: String,
        accountID: String,
        placement: String,
        requestedFields: [String]
    ) {
        self.id = id
        self.agentName = agentName
        self.accountID = accountID
        self.placement = placement
        self.requestedFields = requestedFields
    }
}

/// Coordinator for showing conditional access prompts and waiting for user decisions.
/// Lives on AgentBridge (main actor) and is called from background API threads.
@MainActor
public final class ConditionalAccessPromptCoordinator: ObservableObject {
    @Published public var pendingRequest: ConditionalAccessPromptRequest?
    
    private var continuations: [String: CheckedContinuation<ConditionalAccessDecision, Never>] = [:]
    private var timeoutTasks: [String: Task<Void, Never>] = [:]
    
    public init() {}
    
    /// Request a decision from the user. Suspends until user responds or timeout (30s).
    /// Always returns (never throws); timeout or dismiss → .block (fail-closed).
    public func requestDecision(
        agentName: String,
        accountID: String,
        placement: String,
        requestedFields: [String]
    ) async -> ConditionalAccessDecision {
        let request = ConditionalAccessPromptRequest(
            agentName: agentName,
            accountID: accountID,
            placement: placement,
            requestedFields: requestedFields
        )
        
        return await withCheckedContinuation { continuation in
            self.continuations[request.id] = continuation
            self.pendingRequest = request
            
            // Timeout after 30 seconds → block
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self.resolveRequest(id: request.id, decision: .block)
            }
            self.timeoutTasks[request.id] = timeoutTask
        }
    }
    
    /// User chose Allow.
    public func allow() {
        guard let request = pendingRequest else { return }
        resolveRequest(id: request.id, decision: .allow)
    }
    
    /// User chose Block or dismissed.
    public func block() {
        guard let request = pendingRequest else { return }
        resolveRequest(id: request.id, decision: .block)
    }
    
    private func resolveRequest(id: String, decision: ConditionalAccessDecision) {
        guard let continuation = continuations.removeValue(forKey: id) else { return }
        
        // Cancel timeout
        timeoutTasks.removeValue(forKey: id)?.cancel()
        
        // Clear UI
        if pendingRequest?.id == id {
            pendingRequest = nil
        }
        
        // Resume waiting call
        continuation.resume(returning: decision)
    }
}

/// SwiftUI view for the conditional access prompt dialog.
struct ConditionalAccessPromptDialog: View {
    let request: ConditionalAccessPromptRequest
    let accountLabel: String
    let onAllow: () -> Void
    let onBlock: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Field Access Request")
                        .font(.headline)
                    Text("Agent **\(request.agentName)** wants to read:")
                        .font(.callout)
                }
            }
            
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Mailbox:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(accountLabel) / \(request.placement)")
                        .font(.caption.weight(.medium))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text("Fields:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(request.requestedFields, id: \.self) { field in
                        HStack(spacing: 4) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 4))
                                .foregroundStyle(.secondary)
                            Text(field)
                                .font(.caption.weight(.medium))
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.06))
            )
            
            Text("This permission prompt will dismiss automatically after 30 seconds (Block by default).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            
            HStack(spacing: 10) {
                Button("Block") {
                    onBlock()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Allow") {
                    onAllow()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
