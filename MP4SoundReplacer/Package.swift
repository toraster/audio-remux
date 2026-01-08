// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MP4SoundReplacer",
    platforms: [
        .macOS(.v11)
    ],
    targets: [
        .executableTarget(
            name: "MP4SoundReplacer",
            path: ".",
            exclude: ["Resources", "Entitlements"],
            sources: ["App", "Models", "Views", "ViewModels", "Services"]
        )
    ]
)
