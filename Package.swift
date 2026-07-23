// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HeadsUp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "HeadsUp",
            path: "Sources/HeadsUp"
        )
    ]
)
