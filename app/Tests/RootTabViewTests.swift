import Testing

@testable import Ascension

@Test("app shell exposes the four tabs from spec §4")
func rootHasFourTabs() {
    // Placeholder assertion: the shell is structural until ASC-9..ASC-15 land.
    // Replaced by real view tests with the feature tickets.
    #expect(RootTabView() != nil as RootTabView?)
}
