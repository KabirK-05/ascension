import Foundation
import SwiftData

/// The one manual training input (spec §F2): the heaviest set of an exercise that day.
@Model
public final class TopSetLog {
    /// The local day, `YYYY-MM-DD`.
    public var date: String = ""
    public var exerciseId: String = ""
    public var weightKg: Double = 0
    public var reps: Int = 0
    public var sessionType: SessionKind?

    public init(date: CalendarDate, exerciseId: String, weightKg: Double, reps: Int,
                sessionType: SessionKind? = nil) {
        self.date = date.rawValue
        self.exerciseId = exerciseId
        self.weightKg = weightKg
        self.reps = reps
        self.sessionType = sessionType
    }

    public var calendarDate: CalendarDate? { CalendarDate(rawValue: date) }

    public var topSet: TopSet {
        TopSet(exerciseId: exerciseId, weightKg: weightKg, reps: reps)
    }
}
