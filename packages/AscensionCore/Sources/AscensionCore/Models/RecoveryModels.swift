import Foundation
import SwiftData

/// The morning check-in (spec §F4): soreness per group plus energy on a 1–5 scale.
@Model
public final class CheckIn {
    /// The local day, `YYYY-MM-DD`.
    @Attribute(.unique) public var date: String = ""
    public var energy: Int = 3
    public var chest: SorenessLevel = SorenessLevel.none
    public var back: SorenessLevel = SorenessLevel.none
    public var shoulders: SorenessLevel = SorenessLevel.none
    public var arms: SorenessLevel = SorenessLevel.none
    public var quads: SorenessLevel = SorenessLevel.none
    public var hamstrings: SorenessLevel = SorenessLevel.none
    public var glutes: SorenessLevel = SorenessLevel.none
    public var core: SorenessLevel = SorenessLevel.none

    public init(date: CalendarDate, energy: Int, soreness: Soreness) {
        self.date = date.rawValue
        self.energy = energy
        self.chest = soreness.chest
        self.back = soreness.back
        self.shoulders = soreness.shoulders
        self.arms = soreness.arms
        self.quads = soreness.quads
        self.hamstrings = soreness.hamstrings
        self.glutes = soreness.glutes
        self.core = soreness.core
    }

    public var calendarDate: CalendarDate? { CalendarDate(rawValue: date) }

    public var soreness: Soreness {
        Soreness(chest: chest, back: back, shoulders: shoulders, arms: arms,
                 quads: quads, hamstrings: hamstrings, glutes: glutes, core: core)
    }

    public var rollup: CheckInRollup {
        CheckInRollup(energy: energy, soreness: soreness)
    }
}

/// A scored day from the readiness engine (spec §F5). Mirrored for trends and export.
@Model
public final class ReadinessSnapshot {
    /// The local day, `YYYY-MM-DD`.
    @Attribute(.unique) public var date: String = ""
    public var score: Int = 0
    public var verdict: ReadinessVerdict = ReadinessVerdict.trainAsPlanned
    public var reasons: [String] = []

    public init(date: CalendarDate, score: Int, verdict: ReadinessVerdict,
                reasons: [String]) {
        self.date = date.rawValue
        self.score = score
        self.verdict = verdict
        self.reasons = reasons
    }

    public var calendarDate: CalendarDate? { CalendarDate(rawValue: date) }

    public var rollup: ReadinessRollup {
        ReadinessRollup(score: score, verdict: verdict, reasons: reasons)
    }
}
