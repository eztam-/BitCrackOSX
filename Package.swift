// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CryptKeyFinder",
    platforms: [
        .macOS(.v26), // platform version
    ],
    dependencies: [
        .package(
                url: "https://github.com/21-DOT-DEV/swift-secp256k1",
                exact: "0.21.1"
            ),
        .package(url: "https://github.com/mkrd/Swift-BigInt", exact: "2.3.0"),
        .package(url: "https://github.com/attaswift/BigInt.git", from: "5.7.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "CryptKeyFinder",
            dependencies: [
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "BigNumber", package: "Swift-BigInt"),
                .product(name: "BigInt", package: "BigInt")
            ],
            path: "Sources",
            resources: [.process("SHA256/SHA256.metal")],
        ),
        .testTarget(
            name: "CryptKeyFinderTests",
            dependencies: ["CryptKeyFinder"],
            path: "Tests",
            resources: [
                .process("../Sources/secp256k1/secp256k1.metal"),
                .process("../Sources/KeyGen/KeyGen.metal")
            ],)
    ]
)
