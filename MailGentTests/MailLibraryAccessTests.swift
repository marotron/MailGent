import Testing
@testable import MailGent

@Test func accessDeniedWhenNeitherProbeNorBookmark() {
    let snapshot = MailLibraryAccessSnapshot(
        canListMailDirectory: false,
        hasReadableFolderBookmark: false
    )
    #expect(snapshot.access == .denied)
}

@Test func accessGrantedWhenMailDirectoryListable() {
    let snapshot = MailLibraryAccessSnapshot(
        canListMailDirectory: true,
        hasReadableFolderBookmark: false
    )
    #expect(snapshot.access == .granted)
}

@Test func accessGrantedWhenFolderBookmarkReadable() {
    let snapshot = MailLibraryAccessSnapshot(
        canListMailDirectory: false,
        hasReadableFolderBookmark: true
    )
    #expect(snapshot.access == .granted)
}

@Test func grantedCopyDoesNotClaimFullDiskAccessToggle() {
    let listed = MailLibraryAccessSnapshot(
        canListMailDirectory: true,
        hasReadableFolderBookmark: false
    )
    #expect(listed.headline == "Mail folder readable")
    #expect(listed.explanation.contains("~/Library/Mail"))
    #expect(!listed.explanation.contains("Full Disk Access granted"))

    let bookmark = MailLibraryAccessSnapshot(
        canListMailDirectory: false,
        hasReadableFolderBookmark: true
    )
    #expect(bookmark.headline == "Mail folder readable")
    #expect(bookmark.explanation.contains("folder you chose"))
}

@Test func deniedCopyOffersFolderOrFullDiskAccess() {
    let snapshot = MailLibraryAccessSnapshot(
        canListMailDirectory: false,
        hasReadableFolderBookmark: false
    )
    #expect(snapshot.headline == "Grant access to Mail")
    #expect(snapshot.explanation.contains("Choose Mail Folder"))
    #expect(snapshot.explanation.contains("Full Disk Access"))
}
