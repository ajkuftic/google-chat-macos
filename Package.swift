// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GoogleChat",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GoogleChat",
            path: "Sources/GoogleChat",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)

