// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ArielSplitter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "ArielSplitter", targets: ["ArielSplitter"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "ArielSplitter",
            dependencies: [],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency", .when(configuration: .debug))
            ]
        )
    ]
)
