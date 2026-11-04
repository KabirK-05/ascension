import Foundation

extension Seed {
    /// The program exercises, with the curated cue and common-mistake layer (spec §F2).
    ///
    /// `instructions` and `imageRefs` stay empty on purpose: the free-exercise-db import
    /// (ASC-8) owns them, and inventing them here would be a second source of truth.
    public static let programExercises: [ExerciseDTO] = upperBodyExercises
        + lowerBodyExercises
        + conditioningExercises

    static let upperBodyExercises: [ExerciseDTO] = [
        ExerciseDTO(
            id: SeedExerciseId.dbBenchPress,
            name: "Dumbbell Bench Press",
            primaryMuscles: ["chest"],
            secondaryMuscles: ["triceps", "shoulders"],
            equipment: "dumbbell",
            cues: ["Shoulder blades pinned to the bench", "Wrists stacked over the elbows"],
            commonMistakes: ["Flaring the elbows to 90°", "Bouncing the dumbbells at the top"]),
        ExerciseDTO(
            id: SeedExerciseId.latPulldown,
            name: "Lat Pulldown",
            primaryMuscles: ["lats"],
            secondaryMuscles: ["biceps", "middle back"],
            equipment: "cable",
            cues: ["Chest up, pull the bar to the collarbone", "Drive the elbows down, not back"],
            commonMistakes: ["Leaning back to muscle the weight", "Letting the shoulders shrug up"]),
        ExerciseDTO(
            id: SeedExerciseId.overheadDbPress,
            name: "Overhead Dumbbell Press",
            primaryMuscles: ["shoulders"],
            secondaryMuscles: ["triceps"],
            equipment: "dumbbell",
            cues: ["Ribs down, glutes tight", "Press to a locked-out overhead stack"],
            commonMistakes: ["Arching the lower back", "Pressing in front of the head"]),
        ExerciseDTO(
            id: SeedExerciseId.seatedCableRow,
            name: "Seated Cable Row",
            primaryMuscles: ["middle back"],
            secondaryMuscles: ["lats", "biceps"],
            equipment: "cable",
            cues: ["Tall torso, pull to the navel", "Squeeze the shoulder blades, then release"],
            commonMistakes: ["Rocking the torso for momentum", "Shrugging at the end of the pull"]),
        ExerciseDTO(
            id: SeedExerciseId.inclineDbPress,
            name: "Incline Dumbbell Press",
            primaryMuscles: ["chest"],
            secondaryMuscles: ["shoulders", "triceps"],
            equipment: "dumbbell",
            cues: ["Bench at 30°, no steeper", "Lower to the upper chest, not the throat"],
            commonMistakes: ["Setting the bench too upright", "Letting the elbows drift behind"]),
        ExerciseDTO(
            id: SeedExerciseId.bentOverDbRow,
            name: "Bent-Over Dumbbell Row",
            primaryMuscles: ["middle back"],
            secondaryMuscles: ["lats", "biceps"],
            equipment: "dumbbell",
            cues: ["Hinge to roughly 45°, spine neutral", "Row to the hip, not the armpit"],
            commonMistakes: ["Rounding the lower back", "Standing up as the set gets hard"]),
        ExerciseDTO(
            id: SeedExerciseId.closeGripLatPulldown,
            name: "Close-Grip Lat Pulldown",
            primaryMuscles: ["lats"],
            secondaryMuscles: ["biceps"],
            equipment: "cable",
            cues: ["Neutral grip, elbows tight to the ribs", "Full stretch at the top"],
            commonMistakes: ["Cutting the range short", "Pulling with the biceps alone"]),
        ExerciseDTO(
            id: SeedExerciseId.farmersCarry,
            name: "Farmer's Carry",
            primaryMuscles: ["forearms"],
            secondaryMuscles: ["core", "traps"],
            equipment: "dumbbell",
            cues: ["Tall posture, shoulders down", "Short controlled steps, no leaning"],
            commonMistakes: ["Leaning away from the load", "Rushing and losing the brace"])
    ]

    static let lowerBodyExercises: [ExerciseDTO] = [
        ExerciseDTO(
            id: SeedExerciseId.gobletSquat,
            name: "Goblet Squat",
            primaryMuscles: ["quadriceps"],
            secondaryMuscles: ["glutes", "core"],
            equipment: "dumbbell",
            cues: ["Chest tall, hips back", "Elbows inside the knees at the bottom"],
            commonMistakes: ["Heels lifting off the floor", "Knees collapsing inward"]),
        ExerciseDTO(
            id: SeedExerciseId.dbRomanianDeadlift,
            name: "Dumbbell Romanian Deadlift",
            primaryMuscles: ["hamstrings"],
            secondaryMuscles: ["glutes", "lower back"],
            equipment: "dumbbell",
            cues: ["Soft knees, hips to the wall behind you", "Dumbbells grazing the thighs"],
            commonMistakes: ["Turning it into a squat", "Rounding the back at the bottom"]),
        ExerciseDTO(
            id: SeedExerciseId.walkingLunge,
            name: "Walking Lunge",
            primaryMuscles: ["quadriceps"],
            secondaryMuscles: ["glutes", "hamstrings"],
            equipment: "dumbbell",
            cues: ["Torso upright, step long enough to split the hips", "Back knee just off the floor"],
            commonMistakes: ["Short steps that load only the knee", "Letting the front knee cave"]),
        ExerciseDTO(
            id: SeedExerciseId.plank,
            name: "Plank",
            primaryMuscles: ["abdominals"],
            secondaryMuscles: ["glutes", "shoulders"],
            equipment: "body only",
            cues: ["Elbows under the shoulders", "Ribs down, glutes squeezed, one straight line"],
            commonMistakes: ["Hips sagging or piking up", "Holding the breath"]),
        ExerciseDTO(
            id: SeedExerciseId.legPress,
            name: "Leg Press",
            primaryMuscles: ["quadriceps"],
            secondaryMuscles: ["glutes", "hamstrings"],
            equipment: "machine",
            cues: ["Feet mid-platform, shoulder width", "Stop before the lower back lifts"],
            commonMistakes: ["Locking the knees hard at the top", "Letting the hips roll off the pad"]),
        ExerciseDTO(
            id: SeedExerciseId.hipThrust,
            name: "Hip Thrust",
            primaryMuscles: ["glutes"],
            secondaryMuscles: ["hamstrings"],
            equipment: "barbell",
            cues: ["Chin tucked, ribs down", "Finish with the shins vertical"],
            commonMistakes: ["Hyperextending the lower back at the top", "Pushing through the toes"]),
        ExerciseDTO(
            id: SeedExerciseId.lyingLegCurl,
            name: "Lying Leg Curl",
            primaryMuscles: ["hamstrings"],
            secondaryMuscles: ["calves"],
            equipment: "machine",
            cues: ["Hips pressed into the pad", "Pause at peak contraction"],
            commonMistakes: ["Lifting the hips to finish the rep", "Dropping the weight on the way down"]),
        ExerciseDTO(
            id: SeedExerciseId.hangingLegRaise,
            name: "Hanging Leg Raise",
            primaryMuscles: ["abdominals"],
            secondaryMuscles: ["hip flexors", "forearms"],
            equipment: "body only",
            cues: ["Start from a dead hang, no swing", "Curl the pelvis up, not just the legs"],
            commonMistakes: ["Swinging into the next rep", "Stopping at hip flexion only"])
    ]

    static let conditioningExercises: [ExerciseDTO] = [
        ExerciseDTO(
            id: SeedExerciseId.inclineTreadmillWalk,
            name: "Incline Treadmill Walk",
            primaryMuscles: ["cardiovascular system"],
            secondaryMuscles: ["calves", "glutes"],
            equipment: "machine",
            cues: ["8–10% incline at a conversational pace", "Hands off the rails"],
            commonMistakes: ["Holding the rails and unloading the legs", "Running instead of walking"])
    ]
}
