// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SystemSurfaces",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "SystemSurfaces", targets: ["SystemSurfaces"])],
    dependencies: [
        .package(path: "../AscensionCore"),
        .package(path: "../AscensionEngines")
    ],
    targets: [
        .target(
            name: "SystemSurfaces",
            dependencies: ["AscensionCore", "AscensionEngines"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(name: "SystemSurfacesTests", dependencies: ["SystemSurfaces"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
