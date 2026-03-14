// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Chirp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Chirp",
            path: "Sources/Chirp",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)
