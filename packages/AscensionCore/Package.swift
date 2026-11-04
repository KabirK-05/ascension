// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AscensionCore",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "AscensionCore", targets: ["AscensionCore"])],
    dependencies: [],
    targets: [
        .target(
            name: "AscensionCore",
            resources: [.copy("Resources/ExerciseLibrary")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "AscensionCoreTests", dependencies: ["AscensionCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
