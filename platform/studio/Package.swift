// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "StudioPlatform",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StudioCore", targets: ["StudioCore"]),
        .executable(name: "studio-manager", targets: ["StudioManager"]),
        .executable(name: "studioctl", targets: ["StudioCLI"]),
        .executable(name: "studio-supervisor", targets: ["StudioSupervisor"]),
        .executable(name: "studio-session", targets: ["StudioSession"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "StudioCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "StudioManager", dependencies: ["StudioCore"]),
        .executableTarget(name: "StudioCLI", dependencies: ["StudioCore"]),
        .executableTarget(name: "StudioSupervisor", dependencies: ["StudioCore"]),
        .executableTarget(name: "StudioSession", dependencies: ["StudioCore"]),
        // Tests compile alongside core under the dependency-free local runner.
        // A full native integration suite is still required before activation.
    ]
)
