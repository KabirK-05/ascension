import AscensionCore
import Foundation
import SystemSurfaces
import WidgetKit

/// Writes the shared snapshot the widgets, the App Intents and the notifications read.
///
/// One job, done after every refresh: take the day the ledger now holds and put the five
/// facts §F8 needs into the app group container. Nothing is computed here that a tab does
/// not already compute — the readiness score, the macros and the wins all come straight
/// off the rollup, so a widget and the tab behind it can never disagree.
@MainActor
struct SurfacePublisher {
    private let composition: AppComposition

    init(composition: AppComposition) {
        self.composition = composition
    }

    @discardableResult
    func publish() async -> SurfaceSnapshot {
        let report = await composition.refresher.refresh()
        let program = report.program
        let planned = program.kind(forWeekday: report.today.date.isoWeekday)
        let snapshot = SurfaceSnapshot.from(
            today: report.today,
            history: await composition.ledger.load().all,
            goals: report.goals,
            sessionName: planned.flatMap { program.sessions[$0]?.name })

        if composition.surfaces.write(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
        return snapshot
    }
}
