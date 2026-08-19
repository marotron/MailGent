/// Reads Apple Mail’s on-disk `.emlx` store.
///
/// Domain API (accounts, mailboxes, messages, partial vs complete) is ticket 02.
/// This type exists so the `MailStore` module is a real, testable target now.
public struct MailStore: Sendable {
    public init() {}
}
