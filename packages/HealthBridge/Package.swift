// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HealthBridge",
    platforms: [.iOS(.v26)],
    products: [.library(name: "HealthBridge", targets: ["HealthBridge"])],
    dependencies: [.package(path: "../AscensionCore")],
    targets: [
        .target(name: "HealthBridge", dependencies: ["AscensionCore"]),
        .testTarget(name: "HealthBridgeTests", dependencies: ["HealthBridge"]),
    ]
)
