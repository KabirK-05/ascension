import Foundation

/// Deterministic data for previews and screenshots. Not shipped behaviour —
/// a feature ticket passes real days in.
enum SampleData {
    /// A fixed date, so a preview looks the same in every run and every review.
    static let today: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 11
        components.day = 3
        components.hour = 12
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }()

    static let consistency: [ConsistencyDay] = {
        var generator = Seeded(state: 0x5EED_1234)
        let calendar = Calendar.current
        return (0..<119).reversed().compactMap { back -> ConsistencyDay? in
            guard let date = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            // The first fortnight predates the app, so it has no data at all.
            guard back < 105 else { return ConsistencyDay(date: date, wins: nil) }
            let weekday = calendar.component(.weekday, from: date)
            let roll = generator.next()
            let session: SessionOutcome
            switch (weekday, roll % 10) {
            case (1, _), (7, 0...2): session = .rest
            case (_, 0...1): session = .missed
            default: session = .asPlanned
            }
            return ConsistencyDay(
                date: date,
                wins: DayWins(
                    session: session,
                    proteinGrams: 108 + Int(generator.next() % 62),
                    steps: 5_600 + Int(generator.next() % 9_000),
                    sleepHours: 6.1 + Double(generator.next() % 26) / 10
                )
            )
        }
    }()
}

/// A tiny linear congruential generator. Seeded, so previews never flicker.
private struct Seeded {
    var state: UInt64

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state >> 33
    }
}
