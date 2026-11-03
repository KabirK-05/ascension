import SwiftUI

/// Train tab (F2). Answers: am I on program?
///
/// Scaffolded by ASC-1 — filled in by ASC-10. Intentionally bare:
/// `docs/DESIGN_RULES.md` §1 forbids placeholder copy.
public struct TrainScreen: View {
    public init() {}

    public var body: some View {
        NavigationStack {
            Color.clear
                .navigationTitle("Train")
                .toolbar { ExerciseLibraryToolbarItem() }
        }
    }
}
