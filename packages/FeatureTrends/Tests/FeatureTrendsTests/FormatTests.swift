import Testing

@testable import FeatureTrends

/// Number shape (`docs/DESIGN_RULES.md` §3.2, §3.4).
struct FormatTests {

    @Test(arguments: [
        (73.64, "73.6"), (73.0, "73"), (73.65, "73.7"), (0.0, "0"), (-0.02, "0")
    ])
    func decimalTrimsAndNeverPrintsNegativeZero(_ input: Double, _ expected: String) {
        #expect(TrendsFormat.decimal(input) == expected)
    }

    @Test("a rate carries its direction with a typographic minus")
    func signedDecimalUsesTheTypographicMinus() {
        #expect(TrendsFormat.signedDecimal(-0.42) == "\u{2212}0.42")
        #expect(TrendsFormat.signedDecimal(0.42) == "+0.42")
    }

    @Test("a rate that rounds to zero claims no direction")
    func zeroRateCarriesNoSign() {
        #expect(TrendsFormat.signedDecimal(0.001) == "0")
    }

    @Test("VoiceOver reads a direction as a word, not a glyph")
    func spokenRateIsAWord() {
        #expect(TrendsFormat.spokenSignedDecimal(-0.42, unit: "kilograms per week")
            == "Down 0.42 kilograms per week")
        #expect(TrendsFormat.spokenSignedDecimal(0, unit: "kilograms per week")
            == "No change")
    }

    @Test("a duration keeps its shape at every length")
    func durationKeepsItsShape() {
        #expect(TrendsFormat.duration(minutes: 462) == "7h42")
        #expect(TrendsFormat.duration(minutes: 420) == "7h00")
        #expect(TrendsFormat.duration(minutes: -5) == "0h00")
    }

    @Test("a percentage is an integer — never a precision the data does not have")
    func percentageIsAnInteger() {
        #expect(TrendsFormat.percent(82.4) == "82%")
        #expect(TrendsFormat.percent(100) == "100%")
    }

    @Test("an absent measurement is an em dash, never a zero")
    func absentIsNotZero() {
        #expect(TrendsFormat.optional(nil) == "—")
        #expect(TrendsFormat.optional(0) == "0")
    }
}
