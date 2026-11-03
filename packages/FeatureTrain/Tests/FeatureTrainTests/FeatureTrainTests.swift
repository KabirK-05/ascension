import Testing

@testable import FeatureTrain

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(FeatureTrainModule.schemaVersion == 1)
}
