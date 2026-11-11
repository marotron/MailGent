import MailStore

/// Chooses the propose-send confirm shell. Context never picks the shell —
/// it only optionally adds the left rail inside the extended dialog.
enum ProposeSendConfirmRouting {
    /// Hard invariant: when edit Experimental is on, always return a launch
    /// (extended `SendProposalEditDialog`). When off, `nil` → simple confirm.
    static func editLaunch(
        editExperimental: Bool,
        constants: [SecretConstant],
        agentID: String,
        shortcut: ProposalReferShortcut,
        notePresets: [String],
        roundTrips: Int
    ) -> SendProposalEditLaunch? {
        guard editExperimental else { return nil }
        return SendProposalEditLaunch(
            constants: constants,
            agentID: agentID,
            shortcut: shortcut,
            notePresets: notePresets,
            roundTrips: roundTrips
        )
    }
}
