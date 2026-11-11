import Foundation

/// Pure visibility for optional Cc/Bcc rows on the editable propose-send confirm.
enum OptionalEnvelopeVisibility {
    enum Field: Hashable {
        case cc
        case bcc
    }

    struct Snapshot: Equatable {
        var showCc: Bool
        var showBcc: Bool
        var addable: [Field]
        /// Optional rows the human can dismiss (clear + hide) while editing.
        var removable: [Field]
        var showPlus: Bool
    }

    static func resolve(
        ccEmpty: Bool,
        bccEmpty: Bool,
        revealedCc: Bool,
        revealedBcc: Bool,
        canEdit: Bool
    ) -> Snapshot {
        let showCc = !ccEmpty || revealedCc
        let showBcc = !bccEmpty || revealedBcc
        var addable: [Field] = []
        if canEdit, !showCc { addable.append(.cc) }
        if canEdit, !showBcc { addable.append(.bcc) }
        var removable: [Field] = []
        if canEdit, showCc { removable.append(.cc) }
        if canEdit, showBcc { removable.append(.bcc) }
        return Snapshot(
            showCc: showCc,
            showBcc: showBcc,
            addable: addable,
            removable: removable,
            showPlus: !addable.isEmpty
        )
    }
}
