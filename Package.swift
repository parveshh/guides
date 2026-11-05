// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GuidesCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "GuidesCore", targets: ["GuidesCore"])],
    targets: [
        .target(name: "GuidesCore"),
        .testTarget(name: "GuidesCoreTests", dependencies: ["GuidesCore"])
    ]
)
