import Foundation

/// How numbers are written on this tab.
///
/// Design rule 3.4: never a precision the data does not have. Macros are whole grams,
/// calories are whole kcal, and a portion is whole grams unless it is under ten, where
/// a gram is a tenth of the thing.
enum Figure {
    static func grams(_ value: Double) -> String {
        value < 10 && value != value.rounded()
            ? value.formatted(.number.precision(.fractionLength(1)))
            : value.rounded().formatted(.number.precision(.fractionLength(0)))
    }

    static func whole(_ value: Double) -> String {
        value.rounded().formatted(.number.precision(.fractionLength(0)))
    }

    static func servings(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value == value.rounded() ? 0 : 1)))
    }
}
