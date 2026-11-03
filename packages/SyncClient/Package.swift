// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SyncClient",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "SyncClient", targets: ["SyncClient"])],
    dependencies: [
        .package(path: "../AscensionCore")
    ],
    targets: [
        .target(
            name: "SyncClient",
            dependencies: ["AscensionCore"]
        ),
        .testTarget(name: "SyncClientTests", dependencies: ["SyncClient"])
    ]
)
