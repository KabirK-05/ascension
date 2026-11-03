import AscensionCore
import AscensionEngines
import DesignSystem
import Foundation

/// A ``TodaySnapshot``, turned into the exact strings and fractions the cards draw.
///
/// Pure and synchronous, so every rule on this screen — the rest-day verdict, the
/// summary wording, the grid's intensity — is testable without SwiftUI, HealthKit or a
/// running clock.
public enum TodayPresenter {

    public static func present(_ snapshot: TodaySnapshot) -> TodayPresentation {
        let assessment = ReadinessEngine.assess(snapshot.readinessInput)
        let verdict = VerdictDisplay.of(assessment.verdict,
                                        plannedSession: snapshot.plannedSession,
                                        suggestedSession: assessment.suggestedSession)
        let calendar = ConsistencyMapping.calendar(timezone: snapshot.clock.timezone)

        return TodayPresentation(
            date: ConsistencyMapping.date(of: snapshot.clock.today, in: calendar)
                ?? Date(timeIntervalSince1970: 0),
            summary: SummaryLine.text(for: snapshot, verdict: verdict),
            readiness: ReadinessPanel(score: assessment.score,
                                      verdict: verdict,
                                      reasons: reasons(assessment.reasons)),
            session: plan(for: snapshot, verdict: verdict),
            nutrition: nutrition(for: snapshot),
            measurements: measurements(for: snapshot),
            consistency: consistency(for: snapshot, calendar: calendar))
    }

    // MARK: - Reasons

    /// The engine's two facts, as the card shows them.
    ///
    /// Two things happen here, both presentation and neither a rule change. A sore
    /// region is both the constraint that blocked the session and the measurement that
    /// scored worst, so the engine can legitimately return the same sentence twice —
    /// printed twice it is clutter, and §2.1 says an element the screen works without
    /// does not ship, so the duplicate goes. The survivors get sentence case, because
    /// the engine writes its facts lower-case for the summary line and "HRV" keeps its
    /// capitals either way.
    static func reasons(_ reasons: [String]) -> [String] {
        var seen: Set<String> = []
        return reasons.compactMap { reason in
            let key = reason.lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { return nil }
            return reason.capitalizedFirst
        }
    }

    // MARK: - Session

    /// The session the verdict actually calls for, so the card below the score can never
    /// contradict it: the swap shows the session swapped to, and a rest day or a stand
    /// down shows no card at all.
    static func plan(for snapshot: TodaySnapshot, verdict: VerdictDisplay) -> SessionPlan? {
        guard let kind = verdict.prescribedSession(planned: snapshot.plannedSession),
              kind.isTrainingDay else { return nil }
        return SessionPlan(kind: kind,
                           name: SessionName.of(kind, in: snapshot.program),
                           exercises: snapshot.program.sessions[kind]?.exercises.count ?? 0)
    }

    // MARK: - Nutrition

    static func nutrition(for snapshot: TodaySnapshot) -> NutritionPanel {
        NutritionPanel(kcal: snapshot.today.nutrition.kcal ?? 0,
                       kcalTarget: Double(snapshot.goals.targets.kcal),
                       proteinGrams: snapshot.today.nutrition.proteinG ?? 0,
                       proteinTargetGrams: Double(snapshot.goals.targets.proteinG))
    }

    // MARK: - Measurements

    /// Sleep and its consistency, then the three activity figures spec §F1 asks for.
    /// A missing measurement shows an em dash rather than a zero, and the bedtime row is
    /// dropped entirely when no history stands behind it (§2.1).
    static func measurements(for snapshot: TodaySnapshot) -> [MeasurementRow] {
        let sleep = snapshot.today.sleep
        let targets = snapshot.goals.targets
        var rows = [sleepRow(sleep, targetMinutes: targets.sleepMinutes)]
        if let variation = sleep.consistencySd7Minutes {
            rows.append(bedtimeRow(sdMinutes: variation))
        }
        rows.append(contentsOf: activityRows(snapshot.today.activity, stepTarget: targets.steps))
        return rows
    }

    private static func sleepRow(_ sleep: SleepRollup, targetMinutes: Int) -> MeasurementRow {
        guard let minutes = sleep.asleepMinutes else {
            return MeasurementRow(label: "Sleep",
                                  value: TodayFormat.unmeasured,
                                  spokenValue: TodayFormat.spokenUnmeasured)
        }
        return MeasurementRow(label: "Sleep",
                              value: TodayFormat.duration(minutes: minutes),
                              spokenValue: TodayFormat.spokenDuration(minutes: minutes),
                              progress: fraction(Double(minutes), of: Double(targetMinutes)))
    }

    private static func bedtimeRow(sdMinutes: Double) -> MeasurementRow {
        let minutes = Int(sdMinutes.rounded())
        return MeasurementRow(label: "Bedtime",
                              value: "\u{00B1}\(minutes)",
                              unit: "min",
                              spokenValue: "Varies by \(minutes) minutes")
    }

    private static func activityRows(_ activity: ActivityRollup,
                                     stepTarget: Int) -> [MeasurementRow] {
        [
            MeasurementRow(label: "Steps",
                           value: TodayFormat.optionalCount(activity.steps),
                           spokenValue: spoken(activity.steps.map(TodayFormat.count)),
                           progress: fraction(activity.steps.map(Double.init),
                                              of: Double(stepTarget))),
            MeasurementRow(label: "Energy",
                           value: TodayFormat.optionalCount(activity.activeEnergyKcal),
                           unit: activity.activeEnergyKcal == nil ? nil : "kcal",
                           spokenValue: spoken(activity.activeEnergyKcal.map {
                               "\(TodayFormat.count(Int($0.rounded()))) kilocalories"
                           })),
            MeasurementRow(label: "Exercise",
                           value: TodayFormat.optionalCount(activity.exerciseMinutes),
                           unit: activity.exerciseMinutes == nil ? nil : "min",
                           spokenValue: spoken(activity.exerciseMinutes.map { "\($0) minutes" }))
        ]
    }

    private static func spoken(_ value: String?) -> String {
        value ?? TodayFormat.spokenUnmeasured
    }

    private static func fraction(_ value: Double?, of target: Double) -> Double? {
        guard let value, target > 0 else { return nil }
        return value / target
    }

    // MARK: - Consistency

    static func consistency(for snapshot: TodaySnapshot, calendar: Calendar) -> ConsistencyPanel {
        let end = ConsistencyMapping.date(of: snapshot.clock.today, in: calendar)
            ?? Date(timeIntervalSince1970: 0)
        // Today goes in last, so its live rollup wins if the history already carries a
        // stale copy of the same date. The last cell in the grid is today, part-filled,
        // which is what a contributions grid does and what §6.1's "trailing" means.
        return ConsistencyPanel(
            days: ConsistencyMapping.days(from: snapshot.history + [snapshot.today],
                                          calendar: calendar),
            thresholds: ConsistencyMapping.thresholds(for: snapshot.goals.targets),
            endDate: end,
            calendar: calendar)
    }
}
