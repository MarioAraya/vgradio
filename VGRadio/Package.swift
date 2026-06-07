// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VGRadio",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VGRadio",
            path: "Sources/VGRadio",
            linkerSettings: [.linkedFramework("MediaPlayer")]
        )
    ]
)
