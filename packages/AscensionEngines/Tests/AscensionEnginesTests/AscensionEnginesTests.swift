import Testing
@testable import AscensionEngines

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(AscensionEnginesModule.schemaVersion == 1)
}
