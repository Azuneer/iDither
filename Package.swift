// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "iDither",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "iDither",
            targets: ["iDither"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "iDither",
            resources: [
                .process("Resources")
            ]
        ),
    ]
)
