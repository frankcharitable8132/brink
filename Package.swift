// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Brink",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Brink",
            path: "Sources/Brink",
            resources: [.process("Resources")]
        )
    ]
)
