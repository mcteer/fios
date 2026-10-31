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
    dependencies: [
        .package(url:"https://github.com/open-telemetry/opentelemetry-swift-core.git",exact:"2.4.2")
    ],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "StudioCore", dependencies: ["CSQLite"]),
        .target(name:"StudioObservability",dependencies:["StudioCore",
            .product(name:"OpenTelemetryApi",package:"opentelemetry-swift-core"),
            .product(name:"OpenTelemetrySdk",package:"opentelemetry-swift-core")]),
        .executableTarget(name: "StudioManager", dependencies: ["StudioCore","StudioObservability"]),
        .executableTarget(name: "StudioCLI", dependencies: ["StudioCore"]),
        .executableTarget(name: "StudioSupervisor", dependencies: ["StudioCore"]),
        .executableTarget(name: "StudioSession", dependencies: ["StudioCore"]),
        .testTarget(name:"StudioObservabilityTests",dependencies:["StudioObservability","StudioCore",
            .product(name:"OpenTelemetrySdk",package:"opentelemetry-swift-core")]),
        // Tests compile alongside core under the dependency-free local runner.
        // A full native integration suite is still required before activation.
    ]
)
