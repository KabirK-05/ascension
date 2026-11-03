import AscensionCore
import DesignSystem
import SwiftUI

/// The exercise library (spec §F2). Answers: how do I do this movement?
///
/// Grouped by primary muscle rather than alphabetically, which is the filter most
/// exercise libraries put behind a control (Hevy, Bevel, Google Health all ship an
/// equipment/muscle filter sheet) expressed as section headers instead — same routes
/// in, one fewer control on screen.
public struct ExerciseLibraryScreen: View {
    @State private var exercises: [ExerciseDTO] = []
    @State private var query = ""

    public init() {}

    public var body: some View {
        List {
            if groups.isEmpty {
                muscleShortcuts
            } else {
                ForEach(groups, id: \.muscle) { group in
                    Section(group.muscle.sentenceCased) {
                        ForEach(group.exercises) { exercise in
                            NavigationLink {
                                ExerciseDetailScreen(exercise: exercise)
                            } label: {
                                ExerciseRow(exercise: exercise)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library")
        .searchable(text: $query)
        .task {
            guard exercises.isEmpty else { return }
            exercises = (try? ExerciseLibrary.bundled()) ?? []
        }
    }

    private var groups: [(muscle: String, exercises: [ExerciseDTO])] {
        ExerciseSearch.groupedByPrimaryMuscle(ExerciseSearch.matches(query, in: exercises))
    }

    /// A search that found nothing is a control, not a sentence (§1.4): the muscles
    /// the library does hold, each one a way back into it.
    private var muscleShortcuts: some View {
        ForEach(ExerciseSearch.primaryMuscles(in: exercises), id: \.self) { muscle in
            Button(muscle.sentenceCased) { query = muscle }
                .foregroundStyle(Palette.primaryText)
        }
    }
}

private struct ExerciseRow: View {
    let exercise: ExerciseDTO

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
            Text(exercise.name)
                .foregroundStyle(Palette.primaryText)
            Spacer(minLength: Spacing.snug)
            if let equipment = exercise.equipment {
                Text(equipment)
                    .font(Typography.detail)
                    .foregroundStyle(Palette.secondaryText)
            }
        }
    }
}

#Preview("Library — dark") {
    NavigationStack { ExerciseLibraryScreen() }.preferredColorScheme(.dark)
}

#Preview("Library — light") {
    NavigationStack { ExerciseLibraryScreen() }.preferredColorScheme(.light)
}
