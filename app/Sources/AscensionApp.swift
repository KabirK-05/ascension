import SwiftUI

@main
struct AscensionApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootTabView(composition: delegate.composition)
                .task { await delegate.lifecycle.onForeground() }
        }
    }
}

/// The parts of the app lifecycle SwiftUI does not expose, and the owner of the
/// composition root.
///
/// The composition is built **here**, not in the scene, for one reason:
/// `BGTaskScheduler.register` must be called before
/// `application(_:didFinishLaunchingWithOptions:)` returns, or iOS launches the app for a
/// task with no handler listening. Registering needs the coordinators, the coordinators
/// need the composition, so the composition is built at launch and the few milliseconds
/// SwiftData and the HealthKit adapter cost are paid before the first frame.
///
/// What is deliberately *not* done here is anything that prompts: HealthKit's sheet waits
/// for `onForeground`, so it appears over a drawn screen rather than a blank one.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    private(set) lazy var composition = AppComposition()
    private(set) lazy var lifecycle = AppLifecycle(composition: composition)

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        composition.startup.log()
        lifecycle.registerBackgroundTasks()
        // No authorization prompt: a `content-available` push needs none, which is why
        // `remote-notification` is the only notification entry in `UIBackgroundModes`.
        lifecycle.registrar().register()
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        let registrar = lifecycle.registrar()
        Task { await registrar.received(deviceToken: token) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        // Expected on a simulator, and on any build without an APNs entitlement. The drain
        // still runs on background refresh and on foreground, so there is nothing to
        // recover from here — a silent push only ever makes it sooner.
    }

    /// The silent-push path. `.newData` when a mutation was applied, `.noData` when the
    /// push was not ours or there was nothing queued.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        await lifecycle.handleRemoteNotification(userInfo) ? .newData : .noData
    }
}
