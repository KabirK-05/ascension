import Testing
@testable import FeatureEat

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(FeatureEatModule.schemaVersion == 1)
}
