// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CryptoKeyFinder",
    platforms: [
        .macOS(.v26), // platform version
    ],
    dependencies: [
        .package(
                url: "https://github.com/21-DOT-DEV/swift-secp256k1",
                exact: "0.21.1"
            ),
        .package(url: "https://github.com/mkrd/Swift-BigInt", exact: "2.3.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "CryptoKeyFinder",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "BigNumber", package: "Swift-BigInt")
            ],
            path: "Sources",
            resources: [.process("CryptoKeyFinder/SHA256/SHA256.metal")],
        ),
    ]
)
