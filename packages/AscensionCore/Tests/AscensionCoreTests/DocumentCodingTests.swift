import Foundation
import Testing

@testable import AscensionCore

@Suite("the three documents match §2 of the contract")
struct DocumentCodingTests {
    static let goalSettingsJSON = """
    {
      "version": 7,
      "updatedAt": "2026-11-03T18:00:00-05:00",
      "updatedBy": "muse",
      "targets": { "kcal": 2200, "proteinG": 150, "proteinMinG": 140,
                   "fatMinG": 60, "fatMaxG": 70, "steps": 10000, "sleepMinutes": 450 },
      "body": { "goalWeightKg": 68.0, "heightCm": 170 },
      "programStartDate": "2026-11-03",
      "deloadEveryWeeks": 5,
      "timezone": "America/Toronto",
      "dietaryRules": {
        "excludedMeats": ["pork", "beef"],
        "allowedDairy": ["milk_bournvita"],
        "noLiquidCalories": true
      }
    }
    """

    static let flagsJSON = """
    {
      "version": 2,
      "remoteBridgeEnabled": true,
      "museWritesEnabled": true,
      "museWriteMode": "apply",
      "rawDetailSyncEnabled": false,
      "foundationModelsEnabled": true
    }
    """

    static let mutationJSON = """
    {
      "id": "01JC8X9Y2K3M4N5P6Q7R8S9T0V",
      "createdAt": "2026-11-03T18:00:00-05:00",
      "actor": "muse",
      "kind": "log_meal",
      "payload": { "date": "2026-11-03", "meal": "lunch", "items": [] },
      "appliedAt": null,
      "appliedResult": null
    }
    """

    @Test("the contract's goalSettings example round-trips")
    func goalSettingsRoundTrips() throws {
        let document = try Fixture.decoder.decode(
            GoalSettingsDocument.self, from: Data(Self.goalSettingsJSON.utf8))

        #expect(document.version == 7)
        #expect(document.updatedBy == .muse)
        #expect(document.targets.proteinMinG == 140)
        #expect(document.body.goalWeightKg == 68.0)
        #expect(document.programStartDate.rawValue == "2026-11-03")
        #expect(document.dietaryRules.excludedMeats == ["pork", "beef"])
        #expect(document.dietaryRules.allowedDairy == ["milk_bournvita"])

        let trip = try Fixture.roundTrip(document)
        #expect(trip.value == document)
        #expect(trip.isStable)
    }

    @Test("the contract's flags example round-trips")
    func flagsRoundTrip() throws {
        let document = try Fixture.decoder.decode(
            FlagsDocument.self, from: Data(Self.flagsJSON.utf8))

        #expect(document.museWriteMode == .apply)
        let trip = try Fixture.roundTrip(document)
        #expect(trip.value == document)
        #expect(trip.isStable)
    }

    @Test("a program document round-trips with sessions as a JSON object")
    func programRoundTrips() throws {
        let trip = try Fixture.roundTrip(Seed.program)

        #expect(trip.value == Seed.program)
        #expect(trip.isStable)

        let object = try Fixture.json(trip.first)
        let sessions = try #require(object["sessions"] as? [String: Any])
        #expect(sessions.keys.sorted() == ["lowerA", "lowerB", "upperA", "upperB"])

        let days = try #require(object["days"] as? [[String: Any]])
        #expect(days.count == 7)
    }

    @Test("a mutation keeps appliedAt and appliedResult as explicit nulls")
    func mutationRoundTrips() throws {
        let mutation = try Fixture.decoder.decode(
            Mutation.self, from: Data(Self.mutationJSON.utf8))

        #expect(mutation.kind == .logMeal)
        #expect(mutation.actor == .muse)
        #expect(!mutation.isApplied)
        #expect(mutation.payload.objectValue?["meal"] == .string("lunch"))

        let trip = try Fixture.roundTrip(mutation)
        #expect(trip.value == mutation)
        #expect(trip.isStable)

        let object = try Fixture.json(trip.first)
        #expect(object["appliedAt"] is NSNull)
        #expect(object["appliedResult"] is NSNull)
    }

    @Test("a food item and an exercise round-trip")
    func seedValueTypesRoundTrip() throws {
        for food in Seed.stapleFoods {
            let trip = try Fixture.roundTrip(food)
            #expect(trip.value == food)
            #expect(trip.isStable)
        }
        for exercise in Seed.programExercises {
            let trip = try Fixture.roundTrip(exercise)
            #expect(trip.value == exercise)
            #expect(trip.isStable)
        }
    }

    @Test("the seeded documents round-trip")
    func seedDocumentsRoundTrip() throws {
        let goals = try Fixture.roundTrip(Seed.goalSettings)
        #expect(goals.value == Seed.goalSettings)
        #expect(goals.isStable)

        let flags = try Fixture.roundTrip(Seed.flags)
        #expect(flags.value == Seed.flags)
        #expect(flags.isStable)

        let historical = try Fixture.roundTrip(Seed.historicalProgram)
        #expect(historical.value == Seed.historicalProgram)
        #expect(historical.isStable)
    }
}

@Suite("primitives reject malformed strings")
struct PrimitiveTests {
    @Test("valid calendar dates parse", arguments: ["2026-11-03", "2024-02-29", "2000-02-29"])
    func validDates(_ raw: String) {
        #expect(CalendarDate(rawValue: raw)?.rawValue == raw)
    }

    @Test("malformed calendar dates are rejected",
          arguments: ["2026-13-01", "2026-11-31", "2023-02-29", "1900-02-29",
                      "26-11-03", "2026-1-3", "2026/11/03", "", "2026-11-03T00:00:00"])
    func invalidDates(_ raw: String) {
        #expect(CalendarDate(rawValue: raw) == nil)
    }

    @Test("calendar dates sort chronologically")
    func datesSort() {
        let dates = ["2026-11-10", "2026-02-01", "2025-12-31"].compactMap(CalendarDate.init)
        #expect(dates.sorted().map(\.rawValue) == ["2025-12-31", "2026-02-01", "2026-11-10"])
    }

    @Test("valid timestamps parse",
          arguments: ["2026-11-03T23:05:00-05:00", "2026-11-03T23:05:00Z",
                      "2026-11-03T23:05:00.123-05:00", "2026-11-03T00:00:00+05:30"])
    func validTimestamps(_ raw: String) throws {
        let timestamp = try #require(Timestamp(rawValue: raw))
        #expect(timestamp.date != nil)
    }

    @Test("timestamps without an offset or with a bad clock are rejected",
          arguments: ["2026-11-03T23:05:00", "2026-11-03 23:05:00-05:00",
                      "2026-11-03T25:05:00-05:00", "2026-11-03T23:61:00-05:00",
                      "2026-11-03T23:05:00-5:00", "2026-11-03", ""])
    func invalidTimestamps(_ raw: String) {
        #expect(Timestamp(rawValue: raw) == nil)
    }

    @Test("a timestamp formatted from a date keeps its offset")
    func timestampFromDate() throws {
        let zone = try #require(TimeZone(identifier: "America/Toronto"))
        let stamp = Timestamp(Date(timeIntervalSince1970: 1_793_000_000), timeZone: zone)
        #expect(Timestamp(rawValue: stamp.rawValue) != nil)
        #expect(stamp.rawValue.hasSuffix(":00") )
    }
}
