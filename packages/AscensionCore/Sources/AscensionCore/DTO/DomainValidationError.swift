import Foundation

/// The invariants the contract rejects a write for. Each case names the offending value
/// so a rejection can say what was wrong rather than just that something was.
public enum DomainValidationError: Error, Hashable, Sendable {
    case fatFloorBelowMinimum(Int)
    case fatRangeInverted(min: Int, max: Int)
    case calorieTargetOutOfRange(Int)
    case proteinFloorAboveTarget(min: Int, target: Int)
    case excludedMeatsIncomplete(missing: [String])
    case programDayCountWrong(Int)
    case programWeekdaysInvalid([Int])
    case programSessionMissing(SessionKind)
    case programSessionUnreferenced(SessionKind)
    case programSessionEmpty(SessionKind)
    case muscleRegionTrainedTooSoon(first: Int, second: Int, region: MuscleRegion)
}

extension DomainValidationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .fatFloorBelowMinimum(let grams):
            return "targets.fatMinG must be at least 60 g, found \(grams)"
        case .fatRangeInverted(let min, let max):
            return "targets.fatMinG (\(min)) must not exceed targets.fatMaxG (\(max))"
        case .calorieTargetOutOfRange(let kcal):
            return "targets.kcal must be within 1400...4000, found \(kcal)"
        case .proteinFloorAboveTarget(let min, let target):
            return "targets.proteinMinG (\(min)) must not exceed targets.proteinG (\(target))"
        case .excludedMeatsIncomplete(let missing):
            return "dietaryRules.excludedMeats must contain \(missing.joined(separator: ", "))"
        case .programDayCountWrong(let count):
            return "program.days must hold exactly 7 entries, found \(count)"
        case .programWeekdaysInvalid(let weekdays):
            return "program.days must cover ISO weekdays 1...7 exactly once, found \(weekdays)"
        case .programSessionMissing(let kind):
            return "program.days references \(kind.rawValue) but program.sessions has no entry"
        case .programSessionUnreferenced(let kind):
            return "program.sessions defines \(kind.rawValue) but no day plans it"
        case .programSessionEmpty(let kind):
            return "program.sessions[\(kind.rawValue)] has no exercises"
        case .muscleRegionTrainedTooSoon(let first, let second, let region):
            return "weekdays \(first) and \(second) both train \(region.rawValue) "
                + "less than 48 h apart"
        }
    }
}
