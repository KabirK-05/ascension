// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FeatureToday",
    platforms: [.iOS(.v26)],
    products: [.library(name: "FeatureToday", targets: ["FeatureToday"])],
    dependencies: [
        .package(path: "../AscensionCore"),
        .package(path: "../AscensionEngines"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "FeatureToday",
            dependencies: ["AscensionCore", "AscensionEngines", "DesignSystem"]
        ),
        .testTarget(name: "FeatureTodayTests", dependencies: ["FeatureToday"])
    ]
)
