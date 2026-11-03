// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FeatureEat",
    platforms: [.iOS(.v26)],
    products: [.library(name: "FeatureEat", targets: ["FeatureEat"])],
    dependencies: [
        .package(path: "../AscensionCore"),
        .package(path: "../AscensionEngines"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(
            name: "FeatureEat",
            dependencies: ["AscensionCore", "AscensionEngines", "DesignSystem"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "FeatureEatTests", dependencies: ["FeatureEat"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
