// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ExternalDisplayViewer",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "ExternalDisplayViewer",
            targets: ["ExternalDisplayViewerApp"]
        ),
        .library(
            name: "ExternalDisplayViewerCore",
            targets: ["ExternalDisplayViewerCore"]
        )
    ],
    targets: [
        .target(
            name: "ExternalDisplayViewerCore"
        ),
        .executableTarget(
            name: "ExternalDisplayViewerApp",
            dependencies: ["ExternalDisplayViewerCore"]
        ),
        .testTarget(
            name: "ExternalDisplayViewerCoreTests",
            dependencies: ["ExternalDisplayViewerCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
