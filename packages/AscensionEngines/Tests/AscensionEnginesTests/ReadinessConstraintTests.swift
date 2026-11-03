import AscensionCore
import Foundation
import Testing

@testable import AscensionEngines

/// The hard rules from spec §F5. A failure here means the app can tell the user to train
/// a muscle group it was told not to, which is the one outcome this ticket exists to make
/// impossible.
@Suite("the 48 h and soreness constraints hold")
struct ReadinessConstraintTests {
    // Monday 07:00. 48 h earlier is Saturday 07:00.
    static let exactly48h = "2026-11-07T07:00:00-05:00"
    static let just49h = "2026-11-07T06:00:00-05:00"
    static let just47h = "2026-11-07T08:00:00-05:00"

    @Test("exactly 48 h since the last session is trainable")
    func atTheBoundary() {
        let input = Fix.input(lastTrainedAt: [.upperBody: Fix.stamp(Self.exactly48h)])
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.blockedRegions.isEmpty)
        #expect(assessment.verdict == .trainAsPlanned)
    }

    @Test("an hour past the boundary is trainable")
    func justOutsideTheBoundary() {
        let input = Fix.input(lastTrainedAt: [.upperBody: Fix.stamp(Self.just49h)])
        #expect(ReadinessEngine.assess(input).blockedRegions.isEmpty)
    }

    @Test("an hour inside the boundary is not")
    func justInsideTheBoundary() {
        let input = Fix.input(lastTrainedAt: [.upperBody: Fix.stamp(Self.just47h)])
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.blockedRegions[.upperBody] == .withinRecoveryWindow)
        #expect(assessment.verdict == .swapSession)
    }

    @Test("a region trained an hour ago is blocked")
    func trainedToday() {
        let input = Fix.input(lastTrainedAt: [.upperBody: Fix.stamp("2026-11-09T06:00:00-05:00")])
        #expect(ReadinessEngine.assess(input).blockedRegions[.upperBody] == .withinRecoveryWindow)
    }

    @Test("a region never trained is trainable")
    func neverTrained() {
        let availability = SessionLegality.availability(of: .upperBody, input: Fix.input())
        #expect(availability.hoursSinceTrained == nil)
        #expect(availability.isTrainable)
    }

    @Test("a sore group blocks its region whatever the clock says")
    func soreBlocks() {
        let input = Fix.input(checkIn: Fix.checkIn(sore: [.chest]),
                              lastTrainedAt: [.upperBody: Fix.stamp("2026-10-01T07:00:00-05:00")])
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.blockedRegions[.upperBody] == .sore)
        #expect(assessment.verdict == .swapSession)
    }

    @Test("soreness blocks via every group of its region",
          arguments: [MuscleGroup.chest, .back, .shoulders, .arms])
    func upperGroupsBlockUpper(group: MuscleGroup) {
        let input = Fix.input(checkIn: Fix.checkIn(sore: [group]))
        #expect(ReadinessEngine.assess(input).blockedRegions[.upperBody] == .sore)
    }

    @Test("lower-body groups block lower sessions, not upper ones",
          arguments: [MuscleGroup.quads, .hamstrings, .glutes])
    func lowerGroupsBlockLower(group: MuscleGroup) {
        let upper = Fix.input(planned: .upperA, checkIn: Fix.checkIn(sore: [group]))
        #expect(ReadinessEngine.assess(upper).blockedRegions.isEmpty)

        let lower = Fix.input(planned: .lowerA, checkIn: Fix.checkIn(sore: [group]))
        #expect(ReadinessEngine.assess(lower).blockedRegions[.lowerBody] == .sore)
    }

    @Test("mild soreness does not block")
    func mildDoesNotBlock() {
        let input = Fix.input(checkIn: Fix.checkIn(mild: [.chest, .back]))
        #expect(ReadinessEngine.assess(input).blockedRegions.isEmpty)
    }

    @Test("a last-trained stamp that cannot be read is treated as too soon")
    func unreadableRecency() {
        // A clock whose instant has no parseable date makes the elapsed hours unknowable.
        // The cautious branch blocks; the careless one would recommend training.
        var input = Fix.input(lastTrainedAt: [.upperBody: Fix.stamp("2026-11-07T07:00:00-05:00")])
        input.clock = EngineClock(now: Fix.stamp("2026-11-09T07:00:60-05:00"),
                                  timezone: Seed.timezone)
        let availability = SessionLegality.availability(of: .upperBody, input: input)
        #expect(!availability.recencyKnown)
        #expect(availability.isWithinRecoveryWindow)
        #expect(!availability.isTrainable)
    }

    @Test("a suggested swap is itself legal under the same rules")
    func swapIsLegal() {
        // Upper is sore, so Upper A is out. The swap must be a lower session, and lower
        // must itself be clear.
        let input = Fix.input(planned: .upperA, checkIn: Fix.checkIn(sore: [.back]))
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.verdict == .swapSession)

        guard let swap = assessment.suggestedSession else {
            Issue.record("a swap verdict must name a session")
            return
        }
        let availabilities = SessionLegality.availabilities(input: input)
        #expect(SessionLegality.isLegal(swap, availabilities: availabilities))
        #expect(!swap.trainedRegions.contains(.upperBody))
        #expect(swap.isTrainingDay)
    }

    @Test("a swap is never offered into a region that is also blocked")
    func swapNeverIntoBlockedRegion() {
        // Upper sore and lower trained 12 h ago: no lifting session is legal, so the day
        // stands down rather than swapping into something illegal.
        let input = Fix.input(planned: .upperA,
                              checkIn: Fix.checkIn(sore: [.chest]),
                              lastTrainedAt: [.lowerBody: Fix.stamp("2026-11-08T19:00:00-05:00")])
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.verdict == .activeRecovery)
        #expect(assessment.suggestedSession == nil)
    }

    @Test("conditioning is not a swap, because it is not a lifting session")
    func zone2IsNotASwap() {
        // The only alternative in the program is Zone 2, which loads no region and so
        // would always look "legal". Spec §F5 has no "do cardio instead" verdict, so this
        // is active recovery.
        let input = Fix.input(planned: .upperA,
                              programSessions: [.upperA, .zone2],
                              checkIn: Fix.checkIn(sore: [.shoulders]))
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.verdict == .activeRecovery)
        #expect(assessment.suggestedSession == nil)
    }

    @Test("a full-body plan is blocked by soreness in either half")
    func fullBodyBlockedByEitherHalf() {
        let sessions: Set<SessionKind> = [.fullBody, .upperA, .lowerA]
        let upperSore = Fix.input(planned: .fullBody, programSessions: sessions,
                                  checkIn: Fix.checkIn(sore: [.arms]))
        #expect(ReadinessEngine.assess(upperSore).suggestedSession == .lowerA)

        let lowerSore = Fix.input(planned: .fullBody, programSessions: sessions,
                                  checkIn: Fix.checkIn(sore: [.glutes]))
        #expect(ReadinessEngine.assess(lowerSore).suggestedSession == .upperA)
    }

    @Test("core belongs to no region, so it blocks nothing outright")
    func coreBlocksNoRegion() {
        #expect(!SessionLegality.groups(in: .upperBody).contains(.core))
        #expect(!SessionLegality.groups(in: .lowerBody).contains(.core))

        let input = Fix.input(checkIn: Fix.checkIn(sore: [.core]))
        let assessment = ReadinessEngine.assess(input)
        #expect(assessment.blockedRegions.isEmpty)
        // It is still a brake: a sore core holds a good day back to a capped one.
        #expect(assessment.verdict == .capIntensity)
    }

    @Test("every check-in group is either in a region or explicitly outside one")
    func everyGroupIsAccountedFor() {
        let regioned = Set(MuscleRegion.allCases.flatMap { SessionLegality.groups(in: $0) })
        let outside = Set(SessionLegality.unregionedGroups)
        #expect(regioned.isDisjoint(with: outside))
        #expect(regioned.union(outside) == Set(MuscleGroup.allCases))
    }
}
