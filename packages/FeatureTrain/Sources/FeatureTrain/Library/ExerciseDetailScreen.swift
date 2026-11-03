import AscensionCore
import DesignSystem
import SwiftUI

/// One exercise: how to do it, and the two things that go wrong.
///
/// The curated cues come first and the dataset's step-by-step instructions last.
/// Runna puts its short "Tip" above the long description for the same reason — the
/// two lines are what a lifter reads between sets; the paragraphs are reference.
struct ExerciseDetailScreen: View {
    let exercise: ExerciseDTO

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                ExerciseDemo(exercise: exercise)
                if !exercise.cues.isEmpty {
                    StatCard("Cues") { lines(exercise.cues) }
                }
                if !exercise.commonMistakes.isEmpty {
                    StatCard("Mistakes") { lines(exercise.commonMistakes) }
                }
                StatCard { anatomy }
                if !exercise.instructions.isEmpty {
                    StatCard("Steps") { steps }
                }
            }
            .padding(Spacing.screenMargin)
        }
        .background(Palette.background)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func lines(_ texts: [String]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.regular) {
            ForEach(texts, id: \.self) { text in
                Text(text)
                    .font(Typography.label)
                    .foregroundStyle(Palette.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Label left, value right — the layout Equinox+ uses for equipment and target
    /// muscle, and the one `ValueRow` already is.
    private var anatomy: some View {
        VStack(spacing: Spacing.regular) {
            if let primary = joined(exercise.primaryMuscles) {
                ValueRow("Primary", value: primary)
            }
            if let secondary = joined(exercise.secondaryMuscles) {
                ValueRow("Secondary", value: secondary)
            }
            if let equipment = exercise.equipment {
                ValueRow("Equipment", value: equipment.sentenceCased)
            }
        }
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: Spacing.roomy) {
            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: Spacing.regular) {
                    Text("\(index + 1)")
                        .font(Typography.detail)
                        .monospacedDigit()
                        .foregroundStyle(Palette.tertiaryText)
                    Text(step)
                        .font(Typography.label)
                        .foregroundStyle(Palette.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func joined(_ muscles: [String]) -> String? {
        let listed = muscles.filter { !$0.isEmpty }
        guard !listed.isEmpty else { return nil }
        return ListFormatter.localizedString(byJoining: listed).sentenceCased
    }
}

/// The dataset's two demo frames, start and finish, side by side.
private struct ExerciseDemo: View {
    let exercise: ExerciseDTO

    var body: some View {
        HStack(spacing: Spacing.regular) {
            ForEach(urls, id: \.self) { url in
                Color.clear
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Palette.surface
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercise.name)
    }

    private var urls: [URL] {
        exercise.imageRefs.compactMap { ExerciseLibrary.imageURL(for: $0) }
    }
}

#Preview("Exercise — dark") {
    ExerciseDetailPreview().preferredColorScheme(.dark)
}

#Preview("Exercise — light") {
    ExerciseDetailPreview().preferredColorScheme(.light)
}

private struct ExerciseDetailPreview: View {
    var body: some View {
        NavigationStack {
            ExerciseDetailScreen(exercise: previewExercise)
        }
    }

    private var previewExercise: ExerciseDTO {
        let library = (try? ExerciseLibrary.bundled()) ?? []
        return library.first { $0.id == SeedExerciseId.gobletSquat }
            ?? ExerciseDTO(id: "", name: "", primaryMuscles: [])
    }
}
