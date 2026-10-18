// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenOdometer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TokenOdometer", targets: ["TokenOdometer"])],
    targets: [
        .target(name: "OdometerCore"),
        .executableTarget(name: "TokenOdometer", dependencies: ["OdometerCore"]),
        .testTarget(name: "OdometerCoreTests", dependencies: ["OdometerCore"]),
    ],
    swiftLanguageModes: [.v5]
)
