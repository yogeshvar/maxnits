// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MaxNits",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MaxNits",
            path: "Sources/MaxNits"
        )
    ]
)
