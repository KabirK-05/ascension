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
        // Swift 6 language mode, because `Project.swift` builds the app with
        // `SWIFT_STRICT_CONCURRENCY=complete`. Without it this package compiles under
        // laxer rules than the target that consumes it, and a concurrency error can only
        // surface in the `app` CI job — which is exactly what happened once.
        .target(
            name: "SyncClient",
            dependencies: ["AscensionCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "SyncClientTests",
            dependencies: ["SyncClient"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
