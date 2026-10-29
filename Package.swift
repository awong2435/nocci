// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Nocci",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Nocci", targets: ["Nocci"]),
        .library(name: "NocciCore", targets: ["NocciCore"]),
    ],
    targets: [
        .target(name: "NocciCore"),
        .executableTarget(name: "Nocci", dependencies: ["NocciCore"]),
        .testTarget(name: "NocciCoreTests", dependencies: ["NocciCore"]),
    ]
)
