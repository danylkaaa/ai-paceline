// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AILimits",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "AILimitsCore"),
        .executableTarget(name: "AILimits", dependencies: ["AILimitsCore"]),
        .testTarget(name: "AILimitsCoreTests", dependencies: ["AILimitsCore"]),
    ]
)
