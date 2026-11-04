import Foundation

/// The ids the seeded program references, shaped like free-exercise-db ids.
///
/// The full library import is ASC-8; these are the ~15 program exercises the app needs
/// before that lands. The four Upper A ids are fixed by `docs/EXPORT_SCHEMA.md` §2.2.
public enum SeedExerciseId {
    public static let dbBenchPress = "DB_Bench_Press"
    public static let latPulldown = "Lat_Pulldown"
    public static let overheadDbPress = "Overhead_DB_Press"
    public static let seatedCableRow = "Seated_Cable_Row"
    public static let inclineDbPress = "Incline_DB_Press"
    public static let bentOverDbRow = "Bent_Over_DB_Row"
    public static let closeGripLatPulldown = "Close_Grip_Lat_Pulldown"
    public static let farmersCarry = "Farmers_Carry"
    public static let gobletSquat = "Goblet_Squat"
    public static let dbRomanianDeadlift = "DB_Romanian_Deadlift"
    public static let walkingLunge = "Walking_Lunge"
    public static let plank = "Plank"
    public static let legPress = "Leg_Press"
    public static let hipThrust = "Hip_Thrust"
    public static let lyingLegCurl = "Lying_Leg_Curl"
    public static let hangingLegRaise = "Hanging_Leg_Raise"
    public static let inclineTreadmillWalk = "Incline_Treadmill_Walk"
}
