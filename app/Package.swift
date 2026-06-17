// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fleetmap",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CIOHID"),
        .target(
            name: "FleetCore",
            dependencies: ["CIOHID"],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "fleetdump",
            dependencies: ["FleetCore"]
        ),
        .executableTarget(
            name: "FleetMap",
            dependencies: ["FleetCore"],
            resources: [.process("Resources")]
        ),
    ]
)
