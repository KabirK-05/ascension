// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ExportKit",
    platforms: [.iOS(.v26), .macOS(.v15)],
    products: [.library(name: "ExportKit", targets: ["ExportKit"])],
    dependencies: [.package(path: "../AscensionCore")],
    targets: [
        .target(name: "ExportKit", dependencies: ["AscensionCore"]),
        .testTarget(name: "ExportKitTests", dependencies: ["ExportKit"]),
    ]
)
