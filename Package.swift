// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Overbright",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Overbright",
            path: "Sources/Overbright"
        )
    ]
)
