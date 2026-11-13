// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIPaceline",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "AIPacelineCore"),
        .executableTarget(name: "AIPaceline", dependencies: ["AIPacelineCore"]),
        .testTarget(name: "AIPacelineCoreTests", dependencies: ["AIPacelineCore"]),
    ]
)
