import AscensionCore
import FeatureToday
import Foundation

/// Persists the morning check-in the user taps in Today.
///
/// `TodayModel.checkInStore` is optional and defaults to nil, which is a valid wiring for a
/// preview — and was, until now, also the app's wiring. The effect was asymmetric rather
/// than merely missing: `LocalStore.upsertCheckIn` already existed for Muse's `log_checkin`
/// mutation, so a check-in Muse logged survived a relaunch and one tapped in the app did
/// not. Readiness then abstained on soreness and energy every morning after a cold start,
/// which is the 15 points of coverage ASC-6 documents it giving up when those inputs are
/// absent.
///
/// The upsert is keyed on the date, matching `CheckIn.date`'s `@Attribute(.unique)`, so
/// reopening and re-saving the same day replaces its row rather than failing on the second
/// insert — which is what ASC-14's reopen needs.
struct LocalCheckInStore: CheckInStore {
    private let store: LocalStore

    init(store: LocalStore) {
        self.store = store
    }

    func save(_ checkIn: CheckInRollup, on date: CalendarDate) async throws {
        try await MainActor.run {
            try store.upsertCheckIn(date: date,
                                    energy: checkIn.energy,
                                    soreness: checkIn.soreness)
        }
    }
}
