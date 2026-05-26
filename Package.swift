// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Erudite",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Erudite",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Erudite",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "EruditeTests",
            dependencies: ["Erudite"],
            path: "Tests/EruditeTests"
        ),
    ]
)
