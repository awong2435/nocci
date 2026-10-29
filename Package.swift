// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tuck",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Tuck", targets: ["Tuck"]),
        .library(name: "TuckCore", targets: ["TuckCore"]),
    ],
    targets: [
        .target(name: "TuckCore"),
        .executableTarget(name: "Tuck", dependencies: ["TuckCore"]),
        .testTarget(name: "TuckCoreTests", dependencies: ["TuckCore"]),
    ]
)
