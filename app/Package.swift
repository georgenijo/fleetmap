// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "fleetmap",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FleetCore"),
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
