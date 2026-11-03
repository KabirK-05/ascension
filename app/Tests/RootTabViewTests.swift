import Testing

@testable import Ascension

@Test("the app shell constructs without trapping")
func rootTabViewInitialises() {
    _ = RootTabView()
}
