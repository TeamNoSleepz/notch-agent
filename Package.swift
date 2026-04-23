// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VibeNotch",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VibeNotch",
            linkerSettings: [.linkedFramework("AVFoundation")]
        )
    ]
)
