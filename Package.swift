// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BitCrackOSX",
    platforms: [
        .macOS(.v26), // platform version
    ],
    dependencies: [
        .package(
                url: "https://github.com/21-DOT-DEV/swift-secp256k1",
                exact: "0.21.1"
            ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "BitCrackOSX",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1")
            ],
            path: "Sources",
            resources: [.process("BitCrackOSX/SHA256/SHA256.metal")],
        ),
    ]
)
