// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WindowPac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "WindowPac", path: "Sources/WindowPac")
    ]
)
