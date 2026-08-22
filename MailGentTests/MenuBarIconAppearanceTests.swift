import Testing
@testable import MailGent

struct MenuBarIconAppearanceTests {
    @Test func liveIdleIsTemplateTray() {
        let appearance = MenuBarIconAppearance.resolve(source: .liveMail, pulse: .idle)
        #expect(appearance.symbolName == "tray.full")
        #expect(appearance.isTemplate)
        #expect(appearance.tint == .menuBar)
        #expect(appearance.accessibilityLabel == "MailGent")
    }

    @Test func fixtureIdleIsColoredMasks() {
        let appearance = MenuBarIconAppearance.resolve(source: .fixture, pulse: .idle)
        #expect(appearance.symbolName == "theatermasks.fill")
        #expect(!appearance.isTemplate)
        #expect(appearance.tint == .fixture)
        #expect(appearance.accessibilityLabel == "MailGent fixture mail")
    }

    @Test func fixtureKeepsFakeGlyphOnSuccess() {
        let appearance = MenuBarIconAppearance.resolve(source: .fixture, pulse: .success)
        #expect(appearance.symbolName == "theatermasks.fill")
        #expect(appearance.tint == .success)
        #expect(!appearance.isTemplate)
        #expect(appearance.accessibilityLabel == "MailGent fixture mail")
    }

    @Test func errorPulseUsesWarningOnAnySource() {
        let fixture = MenuBarIconAppearance.resolve(source: .fixture, pulse: .error)
        let live = MenuBarIconAppearance.resolve(source: .liveMail, pulse: .error)
        #expect(fixture.symbolName == "exclamationmark.triangle.fill")
        #expect(live.symbolName == "exclamationmark.triangle.fill")
        #expect(fixture.tint == .error)
        #expect(live.tint == .error)
    }
}
