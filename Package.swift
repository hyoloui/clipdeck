// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Clipdeck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ClipdeckCore", targets: ["ClipdeckCore"]),
        .library(name: "ClipdeckMCPKit", targets: ["ClipdeckMCPKit"]),
        .executable(name: "Clipdeck", targets: ["Clipdeck"]),
        .executable(name: "clipdeck-mcp", targets: ["clipdeck-mcp"]),
    ],
    targets: [
        .target(name: "ClipdeckCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .target(name: "ClipdeckMCPKit", dependencies: ["ClipdeckCore"]),
        .executableTarget(name: "Clipdeck", dependencies: ["ClipdeckCore"]),
        .executableTarget(name: "clipdeck-mcp", dependencies: ["ClipdeckMCPKit"]),
        .testTarget(name: "ClipdeckCoreTests", dependencies: ["ClipdeckCore"]),
        .testTarget(name: "ClipdeckMCPKitTests", dependencies: ["ClipdeckMCPKit"]),
    ]
)
