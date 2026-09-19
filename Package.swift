// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PortWatcherCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PortWatcherCore", targets: ["PortWatcherCore"])
    ],
    targets: [
        .target(name: "PortWatcherCore"),
        .testTarget(name: "PortWatcherCoreTests", dependencies: ["PortWatcherCore"])
    ]
)
