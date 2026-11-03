import Testing

@testable import DesignSystem

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(DesignSystemModule.schemaVersion == 1)
}
