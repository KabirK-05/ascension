import Testing
@testable import SyncClient

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(SyncClientModule.schemaVersion == 1)
}
