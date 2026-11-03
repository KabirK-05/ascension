import ProjectDescription

// The generated .xcodeproj/.xcworkspace are gitignored. See docs/TECH_STACK.md §1.1
// for why this project is generated rather than committed.

let deploymentTarget: DeploymentTargets = .iOS("26.0")
let bundleId = "com.kabirkumar.ascension"

let modules = [
    "AscensionCore", "AscensionEngines", "DesignSystem", "HealthBridge",
    "ExportKit", "SyncClient",
    "FeatureToday", "FeatureTrain", "FeatureEat", "FeatureTrends",
]

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

    // Barcode scanning (F3).
    "NSCameraUsageDescription":
        "Ascension uses the camera to scan food barcodes.",

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
