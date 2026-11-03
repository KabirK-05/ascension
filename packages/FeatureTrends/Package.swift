// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FeatureTrends",
    platforms: [.iOS(.v26)],
    products: [.library(name: "FeatureTrends", targets: ["FeatureTrends"])],
    dependencies: [
        .package(path: "../AscensionCore"),
        .package(path: "../AscensionEngines"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "FeatureTrends",
            dependencies: ["AscensionCore", "AscensionEngines", "DesignSystem"]
        ),
        .testTarget(name: "FeatureTrendsTests", dependencies: ["FeatureTrends"])
    ]
)
