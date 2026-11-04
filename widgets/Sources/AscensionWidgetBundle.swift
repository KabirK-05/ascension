import SwiftUI
import WidgetKit

/// The three widgets spec §F8 asks for: Today, protein, streak.
///
/// No Live Activity. See `docs/PLAN.md` ASC-16 and the ticket's PR for why the optional
/// gym-day card was left out rather than built thin.
@main
struct AscensionWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        EatWidget()
        StreakWidget()
    }
}
