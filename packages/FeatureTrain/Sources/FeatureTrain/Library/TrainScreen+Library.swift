import SwiftUI

/// Reaching the library from Train. The week view that will fill this screen is
/// ASC-10's; this is the one affordance ASC-8 needs and nothing more.
struct ExerciseLibraryToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                ExerciseLibraryScreen()
            } label: {
                Image(systemName: "list.bullet.rectangle")
            }
            .accessibilityLabel("Library")
        }
    }
}
