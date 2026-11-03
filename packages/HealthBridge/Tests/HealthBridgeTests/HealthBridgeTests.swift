import Testing
@testable import HealthBridge

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(HealthBridgeModule.schemaVersion == 1)
}
