import Testing

@testable import ExportKit

@Test("module is pinned to the current schema version")
func schemaVersionIsCurrent() {
    #expect(ExportKitModule.schemaVersion == 1)
}
