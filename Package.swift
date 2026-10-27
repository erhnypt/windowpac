// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "WindowPac",
    platforms: [.macOS("14.0")],
    targets: [
        .executableTarget(name: "WindowPac", path: "Sources/WindowPac")
    ]
)
