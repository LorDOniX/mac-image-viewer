// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImageViewer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "ImageViewer", targets: ["ImageViewer"])],
    targets: [
        .target(name: "ViewerCore"),
        .executableTarget(name: "ImageViewer", dependencies: ["ViewerCore"]),
        .testTarget(name: "ViewerCoreTests", dependencies: ["ViewerCore"])
    ],
    swiftLanguageModes: [.v5]
)
