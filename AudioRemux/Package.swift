// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AudioRemux",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AudioRemux",
            path: ".",
            exclude: ["Resources", "Entitlements"],
            sources: ["App", "Models", "Views", "ViewModels", "Services"]
        )
    ]
)
