// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CryptKeySearch",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        .package(url: "https://github.com/21-DOT-DEV/swift-secp256k1",exact: "0.21.1"),
        .package(url: "https://github.com/mkrd/Swift-BigInt", exact: "2.3.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.6.2"),
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.4"),
    ],
    targets: [
        .executableTarget(
            name: "keysearch",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "BigNumber", package: "Swift-BigInt"),
            ],
            path: "Sources",
            exclude: [
                // We need to exclude metal files that are included into others from the compilation sources.
                // Otherwise, the linker will encounter multiple definitions of the same functions and throw an error.
                //"RIPEMD160/RIPEMD160.metal"
            ],
            resources: [
                /*
                .process("KeyGen/KeyGen.metal"),
                .process("secp256k1/secp256k1.metal"),
                .process("SHA256/SHA256.metal"),
                .process("RIPEMD160/RIPEMD160.metal"),
                .process("BloomFilter/BloomFilter.metal")
                 */
            ],
        ),
        .testTarget(
            name: "KeySearchTests",
            dependencies: [
                "keysearch",
                .product(name: "P256K", package: "swift-secp256k1"),
                .product(name: "BigNumber", package: "Swift-BigInt"),
            ],
            path: "Tests",
            resources: [
                /*
                .process("../Sources/KeyGen/KeyGen.metal"),
                .process("../Sources/secp256k1/secp256k1.metal"),
                .process("../Sources/SHA256/SHA256.metal"),
                .process("../Sources/RIPEMD160/RIPEMD160.metal"),
                .process("../Sources/BloomFilter/BloomFilter.metal")
                 */
            ],)
    ]
)
