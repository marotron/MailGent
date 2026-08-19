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
