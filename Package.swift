// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchAgent",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NotchAgent",
            dependencies: [
                .product(name: "TelemetryClient", package: "SwiftSDK"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/StatusBarIconTemplate.png"),
                .copy("Resources/AppIcon.png"),
            ],
            linkerSettings: [.linkedFramework("AVFoundation")]
        )
    ]
)
