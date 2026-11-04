// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AscensionEngines",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "AscensionEngines", targets: ["AscensionEngines"])],
    dependencies: [
        .package(path: "../AscensionCore")
    ],
    targets: [
        .target(
            name: "AscensionEngines",
            dependencies: ["AscensionCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "AscensionEnginesTests", dependencies: ["AscensionEngines"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
