// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WindowPac",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "WindowPac", path: "Sources/WindowPac")
    ]
)
