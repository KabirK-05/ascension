import Testing

@testable import FeatureTrends

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(FeatureTrendsModule.schemaVersion == 1)
}
