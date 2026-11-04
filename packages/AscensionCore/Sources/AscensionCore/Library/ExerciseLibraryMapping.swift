import Foundation

/// Which free-exercise-db row backs each program exercise.
///
/// `SeedExerciseId` was written before the dataset was in the repo, and only four of
/// its ids happen to match a real one (`Goblet_Squat`, `Plank`, `Leg_Press`,
/// `Hanging_Leg_Raise`). The ids themselves are a contract — `docs/EXPORT_SCHEMA.md`
/// §2.2 pins four of them and the program, top-set logs and the Worker all key on
/// them — so the mismatch is reconciled here instead, and `Seed` is left alone.
///
/// Where the dataset has no exact match the nearest same-pattern row is used and the
/// difference is noted. The dataset only ever supplies instructions and demo images;
/// the name, muscles and equipment the app shows stay `Seed`'s own.
public enum ExerciseLibraryMapping {

    /// Program exercise id → free-exercise-db id.
    public static let databaseIds: [String: String] = [
        SeedExerciseId.dbBenchPress: "Dumbbell_Bench_Press",
        SeedExerciseId.latPulldown: "Wide-Grip_Lat_Pulldown",
        SeedExerciseId.overheadDbPress: "Dumbbell_Shoulder_Press",
        SeedExerciseId.seatedCableRow: "Seated_Cable_Rows",
        SeedExerciseId.inclineDbPress: "Incline_Dumbbell_Press",
        SeedExerciseId.bentOverDbRow: "Bent_Over_Two-Dumbbell_Row",
        SeedExerciseId.closeGripLatPulldown: "Close-Grip_Front_Lat_Pulldown",
        // The dataset calls the loaded carry a walk.
        SeedExerciseId.farmersCarry: "Farmers_Walk",
        SeedExerciseId.gobletSquat: "Goblet_Squat",
        // No dumbbell RDL in the dataset; the stiff-legged dumbbell deadlift is the
        // same hinge with the same cueing.
        SeedExerciseId.dbRomanianDeadlift: "Stiff-Legged_Dumbbell_Deadlift",
        // The walking pattern matters more than the load, and the dataset's only
        // dumbbell lunge is stationary.
        SeedExerciseId.walkingLunge: "Bodyweight_Walking_Lunge",
        SeedExerciseId.plank: "Plank",
        SeedExerciseId.legPress: "Leg_Press",
        SeedExerciseId.hipThrust: "Barbell_Hip_Thrust",
        SeedExerciseId.lyingLegCurl: "Lying_Leg_Curls",
        SeedExerciseId.hangingLegRaise: "Hanging_Leg_Raise",
        // Incline is a setting, not a separate row.
        SeedExerciseId.inclineTreadmillWalk: "Walking_Treadmill"
    ]

    /// The reverse lookup the import needs: dataset id → program exercise id.
    static let programIds: [String: String] = Dictionary(
        databaseIds.map { ($0.value, $0.key) },
        uniquingKeysWith: { first, _ in first })
}
