import ProjectDescription

// The generated .xcodeproj/.xcworkspace are gitignored. See docs/TECH_STACK.md §1.1
// for why this project is generated rather than committed.

let deploymentTarget: DeploymentTargets = .iOS("26.0")
let bundleId = "com.kabirkumar.ascension"

// The app and the widget extension share the app group `group.com.kabirkumar.ascension`,
// declared in `app/Ascension.entitlements` and `widgets/AscensionWidgets.entitlements`. A
// widget runs in its own process with its own container, so that group is the only route a
// number the app measured takes to the Home Screen.

let modules = [
    "AscensionCore", "AscensionEngines", "DesignSystem", "HealthBridge",
    "ExportKit", "SyncClient", "SystemSurfaces",
    "FeatureToday", "FeatureTrain", "FeatureEat", "FeatureTrends",
]

/// What the widget extension needs, and nothing more: the shared snapshot and the design
/// tokens that draw it. No feature package — a widget that imported one would pull four
/// screens and a check-in store into a process that draws one number.
let widgetModules = ["AscensionCore", "AscensionEngines", "DesignSystem", "SystemSurfaces"]

let infoPlist: [String: Plist.Value] = [
    "CFBundleDisplayName": "Ascension",
    "CFBundleShortVersionString": "0.1.0",
    "CFBundleVersion": "1",
    "UILaunchScreen": ["UIColorName": "AccentColor"],
    "UIUserInterfaceStyle": "Automatic",
    "ITSAppUsesNonExemptEncryption": false,

    // HealthKit — spec §6. Read is broad; write is narrow (nutrition, water, body mass).
    "NSHealthShareUsageDescription":
        "Ascension reads your workouts, sleep, heart rate, HRV, steps, energy and body mass to score readiness and track trends.",
    "NSHealthUpdateUsageDescription":
        "Ascension writes the meals and water you log, plus manual weight entries, so they live in Apple Health.",

    // EventKit — planned-vs-done matching (F2).
    "NSCalendarsFullAccessUsageDescription":
        "Ascension reads your calendar to match planned training blocks against completed workouts.",

    // Barcode scanning, and photographing a plate for a macro estimate (F3).
    "NSCameraUsageDescription":
        "Ascension uses the camera to scan food barcodes and to photograph a meal for a macro estimate.",
    // The fallback for the photo estimate where there is no camera, and the way to use
    // a picture taken earlier.
    "NSPhotoLibraryUsageDescription":
        "Ascension reads a photo you choose of a meal to estimate its macros.",

    // The four smart notifications (§F8). No badge: nothing here counts.
    "NSUserNotificationsUsageDescription":
        "Ascension sends your morning readiness, an evening protein nudge when it is still fixable, a training-day check, and the Sunday review.",

    // Nightly export + rollup sync, and the silent push that applies Muse's writes.
    "UIBackgroundModes": ["processing", "remote-notification", "fetch"],
    "BGTaskSchedulerPermittedIdentifiers": [
        "\(bundleId).nightly-export",
        "\(bundleId).rollup-sync",
    ],
]

let project = Project(
    name: "Ascension",
    organizationName: "Kabir Kumar",
    packages: modules.map { .local(path: .relativeToRoot("packages/\($0)")) },
    settings: .settings(
        base: [
            "SWIFT_VERSION": "6.0",
            "SWIFT_STRICT_CONCURRENCY": "complete",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS": "NO",
            "CODE_SIGN_STYLE": "Automatic",
            "ENABLE_USER_SCRIPT_SANDBOXING": "YES",
        ],
        configurations: [.debug(name: "Debug"), .release(name: "Release")]
    ),
    targets: [
        .target(
            name: "Ascension",
            destinations: .iOS,
            product: .app,
            bundleId: bundleId,
            deploymentTargets: deploymentTarget,
            infoPlist: .extendingDefault(with: infoPlist),
            sources: ["app/Sources/**"],
            resources: ["app/Resources/**"],
            entitlements: "app/Ascension.entitlements",
            dependencies: modules.map { .package(product: $0) }
                + [.target(name: "AscensionWidgets")]
        ),
        .target(
            name: "AscensionWidgets",
            destinations: .iOS,
            product: .appExtension,
            bundleId: "\(bundleId).widgets",
            deploymentTargets: deploymentTarget,
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Ascension",
                // An extension's version has to match its container's, or the build warns
                // and the App Store refuses the pair.
                "CFBundleShortVersionString": "0.1.0",
                "CFBundleVersion": "1",
                "NSExtension": [
                    "NSExtensionPointIdentifier": "com.apple.widgetkit-extension",
                ],
            ]),
            sources: ["widgets/Sources/**"],
            entitlements: "widgets/AscensionWidgets.entitlements",
            dependencies: widgetModules.map { .package(product: $0) }
        ),
        .target(
            name: "AscensionTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "\(bundleId).tests",
            deploymentTargets: deploymentTarget,
            infoPlist: .default,
            sources: ["app/Tests/**"],
            dependencies: [.target(name: "Ascension")]
        ),
    ]
)
