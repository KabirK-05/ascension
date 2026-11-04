import Foundation
import Testing

@testable import AscensionCore

@Suite("DayRollup matches the §1 contract")
struct DayRollupCodingTests {
    @Test("the contract's own example decodes field for field")
    func contractExampleDecodes() throws {
        let data = Data(Fixture.dayRollupJSON.utf8)
        let rollup = try Fixture.decoder.decode(DayRollup.self, from: data)

        #expect(rollup.date.rawValue == "2026-11-03")
        #expect(rollup.timezone == "America/Toronto")
        #expect(rollup.nutrition.proteinG == 148)
        #expect(rollup.activity.steps == 10_240)
        #expect(rollup.sleep.asleepMinutes == 462)
        #expect(rollup.vitals.vo2Max == 44.2)
        #expect(rollup.body.rateKgPerWeek == -0.4)
        #expect(rollup.body.bodyFatPct == nil)
        #expect(rollup.training.sessionPlanned == .upperA)
        #expect(rollup.training.sessionDone)
        #expect(rollup.training.workouts.count == 1)
        #expect(rollup.training.workouts.first?.timeInZonesMinutes.z2 == 22)
        #expect(rollup.training.topSets.map(\.exerciseId) == ["Goblet_Squat", "DB_Bench_Press"])
        #expect(rollup.checkIn?.energy == 4)
        #expect(rollup.checkIn?.soreness.quads == .sore)
        #expect(rollup.readiness?.verdict == .trainAsPlanned)
        #expect(rollup.wins.total == 4)
    }

    @Test("a decoded rollup re-encodes to the same bytes")
    func roundTripsByteForByte() throws {
        let original = try Fixture.decoder.decode(
            DayRollup.self, from: Data(Fixture.dayRollupJSON.utf8))
        let trip = try Fixture.roundTrip(original)

        #expect(trip.value == original)
        #expect(trip.isStable)
    }

    @Test("an unmeasured field is written as an explicit null, never omitted")
    func unmeasuredFieldsEncodeAsNull() throws {
        let rollup = Fixture.rollup()
        let encoded = try Fixture.encoder.encode(rollup)
        let object = try Fixture.json(encoded)

        let body = try #require(object["body"] as? [String: Any])
        #expect(body.keys.sorted() == ["bodyFatPct", "rateKgPerWeek", "waistCm",
                                       "weightAvg7Kg", "weightKg"])
        #expect(body["weightKg"] is NSNull)
        #expect(object["checkIn"] is NSNull)
        #expect(object["readiness"] is NSNull)
    }

    @Test("every group the contract names is present at the top level")
    func topLevelShapeIsComplete() throws {
        let encoded = try Fixture.encoder.encode(Fixture.rollup())
        let object = try Fixture.json(encoded)

        #expect(object.keys.sorted() == ["activity", "body", "checkIn", "date",
                                         "nutrition", "readiness", "sleep", "timezone",
                                         "training", "updatedAt", "vitals", "wins"])
    }
}

@Suite("closed sets reject anything outside them")
struct ClosedSetTests {
    @Test("an unknown session kind fails to decode instead of defaulting",
          arguments: ["upperC", "UPPERA", "cardio", ""])
    func unknownSessionKindFails(_ raw: String) throws {
        let json = #"{"sessionPlanned":"\#(raw)","sessionDone":false,"loadAu":null,"#
            + #""workouts":[],"topSets":[]}"#
        #expect(throws: (any Error).self) {
            try Fixture.decoder.decode(TrainingRollup.self, from: Data(json.utf8))
        }
    }

    @Test("an unknown readiness verdict fails to decode")
    func unknownVerdictFails() throws {
        let json = #"{"score":80,"verdict":"trainHard","reasons":[]}"#
        #expect(throws: (any Error).self) {
            try Fixture.decoder.decode(ReadinessRollup.self, from: Data(json.utf8))
        }
    }

    @Test("an unknown soreness level fails to decode")
    func unknownSorenessFails() throws {
        let json = #"{"chest":"none","back":"wrecked","shoulders":"none","arms":"none","#
            + #""quads":"none","hamstrings":"none","glutes":"none","core":"none"}"#
        #expect(throws: (any Error).self) {
            try Fixture.decoder.decode(Soreness.self, from: Data(json.utf8))
        }
    }

    @Test("an unknown mutation kind fails to decode")
    func unknownMutationKindFails() throws {
        let json = #"{"id":"01JC","createdAt":"2026-11-03T18:00:00-05:00","actor":"muse","#
            + #""kind":"delete_everything","payload":{},"appliedAt":null,"appliedResult":null}"#
        #expect(throws: (any Error).self) {
            try Fixture.decoder.decode(Mutation.self, from: Data(json.utf8))
        }
    }

    @Test("energy outside 1–5 fails to decode", arguments: [0, 6, -1, 99])
    func energyOutOfRangeFails(_ energy: Int) throws {
        let soreness = #"{"chest":"none","back":"none","shoulders":"none","arms":"none","#
            + #""quads":"none","hamstrings":"none","glutes":"none","core":"none"}"#
        let json = #"{"energy":\#(energy),"soreness":\#(soreness)}"#
        #expect(throws: (any Error).self) {
            try Fixture.decoder.decode(CheckInRollup.self, from: Data(json.utf8))
        }
    }

    @Test("wins.total outside 0–4 fails to decode", arguments: [-1, 5])
    func winsTotalOutOfRangeFails(_ total: Int) throws {
        let json = #"{"session":true,"protein":true,"steps":true,"sleep":true,"#
            + #""total":\#(total)}"#
        #expect(throws: (any Error).self) {
            try Fixture.decoder.decode(Wins.self, from: Data(json.utf8))
        }
    }

    @Test("every meal kind in the contract decodes", arguments: MealKind.allCases)
    func mealKindsDecode(_ kind: MealKind) throws {
        let decoded = try Fixture.decoder.decode(
            MealKind.self, from: Data(#""\#(kind.rawValue)""#.utf8))
        #expect(decoded == kind)
    }

    @Test("mutation kinds use the contract's snake_case spellings")
    func mutationKindSpellings() {
        #expect(Set(MutationKind.allCases.map(\.rawValue)) == [
            "set_targets", "update_program", "set_staples", "set_flag",
            "accept_suggestion", "log_meal", "log_water", "log_top_set",
            "log_checkin", "schedule_workout", "trigger_export"
        ])
    }

    @Test("Tier-2 kinds are the ones the device applies")
    func tiersMatchTheContract() {
        let tierTwo = MutationKind.allCases.filter { $0.tier == 2 }.map(\.rawValue)
        #expect(Set(tierTwo) == ["log_meal", "log_water", "log_top_set", "log_checkin",
                                 "schedule_workout", "trigger_export"])
    }
}
