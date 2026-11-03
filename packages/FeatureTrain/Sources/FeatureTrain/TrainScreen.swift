import AscensionCore
import DesignSystem
import SwiftUI

/// Train tab (F2). Answers: am I on program?
///
/// Three cards and nothing else: the week with the adherence behind it, the session
/// ahead with the loads the progression rule chose, and the session behind with what it
/// cost. Everything further in — the zone breakdown, the comparison with the last
/// session of the same kind — is a tap away rather than a fourth card (§5.3).
///
/// Apple records the session; this screen schedules it, reads it back and interprets it.
public struct TrainScreen: View {
    @State private var model: TrainModel
    @State private var selected: SessionDebrief?
    @State private var logging: TrainingDay?

    public init(environment: TrainEnvironment = .unwired) {
        _model = State(initialValue: TrainModel(environment: environment))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.section) {
                    WeekCard(week: model.week, adherence: model.adherence, streak: model.streak,
                             timeZone: model.timeZone, today: today, onSelect: select)
                    if let next = model.next {
                        NextSessionCard(day: next, targets: model.targets,
                                        canSendToWatch: model.canSendToWatch,
                                        name: model.name(ofExercise:),
                                        onSendToWatch: { send(next) })
                    }
                    if let last = model.last, let debrief = model.debrief(for: last) {
                        Button { selected = debrief } label: {
                            LastSessionCard(debrief: debrief, timeZone: model.timeZone)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.screenMargin)
            }
            .background(Palette.background)
            .navigationTitle("Train")
            .toolbar { ExerciseLibraryToolbarItem() }
            .navigationDestination(item: $selected) { debrief in
                SessionDebriefScreen(debrief: debrief, timeZone: model.timeZone,
                                     onLogTopSets: { logging = debrief.day })
            }
            .sheet(item: $logging) { day in
                TopSetLogScreen(sessionName: day.sessionName,
                                drafts: model.logDraft(for: day)) { drafts in
                    Task { await model.save(drafts, on: day.date, kind: day.planned) }
                }
            }
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }

    private var today: CalendarDate {
        TrainDay.of(Date(), timeZone: model.timeZone)
    }

    private func select(_ day: TrainingDay) {
        selected = model.debrief(for: day)
    }

    /// A failure to reach the Watch is the Watch's answer, not a state this screen keeps:
    /// the week is still the week, and a message about it would be the explanatory
    /// clutter §1 exists to prevent.
    private func send(_ day: TrainingDay) {
        Task { try? await model.sendToWatch(day) }
    }
}

#Preview("Train — dark") {
    TrainScreen(environment: .preview).preferredColorScheme(.dark)
}

#Preview("Train — light") {
    TrainScreen(environment: .preview).preferredColorScheme(.light)
}
