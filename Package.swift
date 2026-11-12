// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "notchjam",
    platforms: [.macOS(.v14)],
    products: [.library(name: "NotchjamCore", targets: ["NotchjamCore"])],
    targets: [
        .target(name: "NotchjamCore", path: "notchjam/Core"),
        .testTarget(name: "NotchjamCoreTests", dependencies: ["NotchjamCore"], path: "notchjamTests")
    ]
)
