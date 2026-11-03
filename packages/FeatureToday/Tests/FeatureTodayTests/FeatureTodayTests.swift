import Testing

@testable import FeatureToday

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(FeatureTodayModule.schemaVersion == 1)
}
