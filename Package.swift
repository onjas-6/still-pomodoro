// swift-tools-version: 6.0
// Created 2026-09-15 · gpt-6-astra · Codex
import PackageDescription

let package = Package(
    name: "Still",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Still", targets: ["Still"])],
    targets: [
        .target(name: "StillCore"),
        .executableTarget(name: "Still", dependencies: ["StillCore"]),
        .testTarget(name: "StillCoreTests", dependencies: ["StillCore"])
    ],
    swiftLanguageModes: [.v5]
)
