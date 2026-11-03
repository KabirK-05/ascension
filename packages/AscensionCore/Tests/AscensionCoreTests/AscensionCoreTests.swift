import Testing

@testable import AscensionCore

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(AscensionCoreModule.schemaVersion == 1)
}
