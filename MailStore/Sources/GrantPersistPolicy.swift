import Foundation

/// Decides whether a grant save may replace `grants.json`.
///
/// Pairing and other incidental saves must not replace a non-empty (or unreadable)
/// grant file with an empty list. An explicit clear or agent revoke may.
public enum GrantPersistPolicy {
    public static func shouldKeepExistingFile(
        diskGrantCount: Int?,
        diskReadable: Bool,
        nextGrantCount: Int,
        allowsEmptyOverwrite: Bool
    ) -> Bool {
        if nextGrantCount > 0 { return false }
        if allowsEmptyOverwrite { return false }
        if !diskReadable { return true }
        if let diskGrantCount, diskGrantCount > 0 { return true }
        return false
    }

    /// In-memory grants plus on-disk grants whose agent is not paired and not being dropped.
    /// Stops a later save from deleting rows that belong to a previous agent id.
    public static func mergedGrants(
        memory: [Grant],
        disk: [Grant],
        pairedAgentIDs: Set<String>,
        dropAgentIDs: Set<String>
    ) -> [Grant] {
        let live = memory.filter { !dropAgentIDs.contains($0.agentID) }
        let orphans = disk.filter { grant in
            !pairedAgentIDs.contains(grant.agentID) && !dropAgentIDs.contains(grant.agentID)
        }
        return live + orphans
    }
}
