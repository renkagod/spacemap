// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpaceMap",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SpaceMapCore"),
        .executableTarget(name: "SpaceMap", dependencies: ["SpaceMapCore"]),
        .testTarget(name: "SpaceMapCoreTests", dependencies: ["SpaceMapCore"]),
    ]
)
