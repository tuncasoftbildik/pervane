// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pervane",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CSMC", linkerSettings: [.linkedFramework("IOKit")]),
        .target(name: "PervaneCore", dependencies: ["CSMC"]),
        .executableTarget(name: "pervaned", dependencies: ["PervaneCore"]),
        .executableTarget(name: "pervane", dependencies: ["PervaneCore"]),
        .executableTarget(name: "PervaneApp", dependencies: ["PervaneCore"]),
        .testTarget(name: "PervaneCoreTests", dependencies: ["PervaneCore"]),
    ]
)
