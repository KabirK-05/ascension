// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FeatureTrain",
    platforms: [.iOS(.v26)],
    products: [.library(name: "FeatureTrain", targets: ["FeatureTrain"])],
    dependencies: [
        .package(path: "../AscensionCore"),
        .package(path: "../AscensionEngines"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "FeatureTrain",
            dependencies: ["AscensionCore", "AscensionEngines", "DesignSystem"]
        ),
        .testTarget(name: "FeatureTrainTests", dependencies: ["FeatureTrain"])
    ]
)
