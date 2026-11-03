import Foundation

extension Seed {
    /// The 15-minute incline-walk finisher slot, appended to two lifting days a week.
    private static func finisherSlot(order: Int) -> SessionExerciseEntry {
        SessionExerciseEntry(order: order, exerciseId: SeedExerciseId.inclineTreadmillWalk,
                             sets: 1, repsLow: 1, repsHigh: 1, finisher: true)
    }

    /// A hold or carry: one effort per set, so reps do not apply.
    private static func holdSlot(order: Int, exerciseId: String) -> SessionExerciseEntry {
        SessionExerciseEntry(order: order, exerciseId: exerciseId,
                             sets: 3, repsLow: 1, repsHigh: 1)
    }

    static let upperASession = SessionTemplateEntry(name: "Upper A", exercises: [
        SessionExerciseEntry(order: 1, exerciseId: SeedExerciseId.dbBenchPress),
        SessionExerciseEntry(order: 2, exerciseId: SeedExerciseId.latPulldown),
        SessionExerciseEntry(order: 3, exerciseId: SeedExerciseId.overheadDbPress),
        SessionExerciseEntry(order: 4, exerciseId: SeedExerciseId.seatedCableRow),
        finisherSlot(order: 5)
    ])

    static let upperBSession = SessionTemplateEntry(name: "Upper B", exercises: [
        SessionExerciseEntry(order: 1, exerciseId: SeedExerciseId.inclineDbPress),
        SessionExerciseEntry(order: 2, exerciseId: SeedExerciseId.bentOverDbRow),
        SessionExerciseEntry(order: 3, exerciseId: SeedExerciseId.closeGripLatPulldown),
        holdSlot(order: 4, exerciseId: SeedExerciseId.farmersCarry)
    ])

    static let lowerASession = SessionTemplateEntry(name: "Lower A", exercises: [
        SessionExerciseEntry(order: 1, exerciseId: SeedExerciseId.gobletSquat),
        SessionExerciseEntry(order: 2, exerciseId: SeedExerciseId.dbRomanianDeadlift),
        SessionExerciseEntry(order: 3, exerciseId: SeedExerciseId.walkingLunge),
        holdSlot(order: 4, exerciseId: SeedExerciseId.plank)
    ])

    static let lowerBSession = SessionTemplateEntry(name: "Lower B", exercises: [
        SessionExerciseEntry(order: 1, exerciseId: SeedExerciseId.legPress),
        SessionExerciseEntry(order: 2, exerciseId: SeedExerciseId.hipThrust),
        SessionExerciseEntry(order: 3, exerciseId: SeedExerciseId.lyingLegCurl),
        SessionExerciseEntry(order: 4, exerciseId: SeedExerciseId.hangingLegRaise),
        finisherSlot(order: 5)
    ])

    /// The current direction (spec §3): Mon upper, Tue lower, Thu upper, Fri lower, with
    /// every group trained twice a week and never inside 48 h.
    public static let program = ProgramDocument(
        version: 1,
        updatedAt: seededAt,
        updatedBy: .device,
        name: "Upper/Lower 4-day",
        days: [
            ProgramDayEntry(weekday: 1, kind: .upperA),
            ProgramDayEntry(weekday: 2, kind: .lowerA),
            ProgramDayEntry(weekday: 3, kind: .rest),
            ProgramDayEntry(weekday: 4, kind: .upperB),
            ProgramDayEntry(weekday: 5, kind: .lowerB),
            ProgramDayEntry(weekday: 6, kind: .rest),
            ProgramDayEntry(weekday: 7, kind: .rest)
        ],
        sessions: [
            .upperA: upperASession,
            .lowerA: lowerASession,
            .upperB: upperBSession,
            .lowerB: lowerBSession
        ],
        progression: ProgressionSettings(rule: .rir2, incrementKg: 2.5),
        finisher: FinisherSettings(kind: .inclineWalk, minutes: 15,
                                   inclinePct: 9, daysPerWeek: 2),
        deload: DeloadSettings(active: false, loadFactor: 0.6, volumeFactor: 0.5))
}

extension Seed {
    static let fullBodySession = SessionTemplateEntry(name: "Full Body", exercises: [
        SessionExerciseEntry(order: 1, exerciseId: SeedExerciseId.gobletSquat),
        SessionExerciseEntry(order: 2, exerciseId: SeedExerciseId.dbBenchPress),
        SessionExerciseEntry(order: 3, exerciseId: SeedExerciseId.bentOverDbRow),
        SessionExerciseEntry(order: 4, exerciseId: SeedExerciseId.dbRomanianDeadlift),
        SessionExerciseEntry(order: 5, exerciseId: SeedExerciseId.overheadDbPress),
        holdSlot(order: 6, exerciseId: SeedExerciseId.plank)
    ])

    static let zone2Session = SessionTemplateEntry(name: "Zone 2", exercises: [
        SessionExerciseEntry(order: 1, exerciseId: SeedExerciseId.inclineTreadmillWalk,
                             sets: 1, repsLow: 1, repsHigh: 1)
    ])

    /// The historical baseline (spec §3): Mon/Thu full body, Wed/Sat Zone 2.
    ///
    /// Seeded alongside the current block to keep the proof honest — the model holds
    /// both shapes because the week is seven slots pointing at named sessions, not four
    /// hardcoded days.
    public static let historicalProgram = ProgramDocument(
        version: 1,
        updatedAt: seededAt,
        updatedBy: .device,
        name: "Full Body + Zone 2",
        days: [
            ProgramDayEntry(weekday: 1, kind: .fullBody),
            ProgramDayEntry(weekday: 2, kind: .rest),
            ProgramDayEntry(weekday: 3, kind: .zone2),
            ProgramDayEntry(weekday: 4, kind: .fullBody),
            ProgramDayEntry(weekday: 5, kind: .rest),
            ProgramDayEntry(weekday: 6, kind: .zone2),
            ProgramDayEntry(weekday: 7, kind: .rest)
        ],
        sessions: [
            .fullBody: fullBodySession,
            .zone2: zone2Session
        ],
        progression: ProgressionSettings(rule: .rir2, incrementKg: 2.5),
        finisher: FinisherSettings(kind: .inclineWalk, minutes: 15,
                                   inclinePct: 9, daysPerWeek: 0),
        deload: DeloadSettings(active: false, loadFactor: 0.6, volumeFactor: 0.5))
}
