// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BarongNotch",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "BarongNotch", targets: ["BarongNotch"])
    ],
    targets: [
        .executableTarget(
            name: "BarongNotch",
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
