import Testing
@testable import MailGent

struct OptionalEnvelopeVisibilityTests {
    @Test func bothEmptyAndEditableShowsPlusWithCcAndBcc() {
        let snap = OptionalEnvelopeVisibility.resolve(
            ccEmpty: true,
            bccEmpty: true,
            revealedCc: false,
            revealedBcc: false,
            canEdit: true
        )
        #expect(snap.showCc == false)
        #expect(snap.showBcc == false)
        #expect(snap.addable == [.cc, .bcc])
        #expect(snap.showPlus)
    }

    @Test func ccOnlyDraftAddsBccToMenu() {
        let snap = OptionalEnvelopeVisibility.resolve(
            ccEmpty: false,
            bccEmpty: true,
            revealedCc: false,
            revealedBcc: false,
            canEdit: true
        )
        #expect(snap.showCc)
        #expect(snap.showBcc == false)
        #expect(snap.addable == [.bcc])
        #expect(snap.showPlus)
    }

    @Test func bothVisibleHidesPlus() {
        let snap = OptionalEnvelopeVisibility.resolve(
            ccEmpty: false,
            bccEmpty: false,
            revealedCc: true,
            revealedBcc: true,
            canEdit: true
        )
        #expect(snap.showCc)
        #expect(snap.showBcc)
        #expect(snap.addable.isEmpty)
        #expect(snap.showPlus == false)
    }

    @Test func clearAfterRevealHidesRowAndReturnsFieldToMenu() {
        let snap = OptionalEnvelopeVisibility.resolve(
            ccEmpty: true,
            bccEmpty: true,
            revealedCc: false,
            revealedBcc: false,
            canEdit: true
        )
        #expect(snap.showCc == false)
        #expect(snap.addable.contains(.cc))
        #expect(snap.showPlus)
    }

    @Test func revealedEmptyStillShowsUntilClearedFlag() {
        let snap = OptionalEnvelopeVisibility.resolve(
            ccEmpty: true,
            bccEmpty: true,
            revealedCc: true,
            revealedBcc: false,
            canEdit: true
        )
        #expect(snap.showCc)
        #expect(snap.addable == [.bcc])
        #expect(snap.showPlus)
    }

    @Test func cannotEditHidesPlusEvenWhenFieldsMissing() {
        let snap = OptionalEnvelopeVisibility.resolve(
            ccEmpty: true,
            bccEmpty: true,
            revealedCc: false,
            revealedBcc: false,
            canEdit: false
        )
        #expect(snap.showCc == false)
        #expect(snap.showBcc == false)
        #expect(snap.addable.isEmpty)
        #expect(snap.removable.isEmpty)
        #expect(snap.showPlus == false)
    }

    @Test func visibleOptionalFieldsAreRemovableWhileEditing() {
        let snap = OptionalEnvelopeVisibility.resolve(
            ccEmpty: false,
            bccEmpty: true,
            revealedCc: false,
            revealedBcc: true,
            canEdit: true
        )
        #expect(snap.removable == [.cc, .bcc])
        #expect(snap.addable.isEmpty)
        #expect(snap.showPlus == false)
    }

    @Test func hiddenOptionalFieldsAreNotRemovable() {
        let snap = OptionalEnvelopeVisibility.resolve(
            ccEmpty: true,
            bccEmpty: true,
            revealedCc: false,
            revealedBcc: false,
            canEdit: true
        )
        #expect(snap.removable.isEmpty)
    }
}
