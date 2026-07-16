// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UseCard",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "UseCardCore", targets: ["UseCardCore"])
    ],
    targets: [
        .target(name: "UseCardCore"),
        .testTarget(name: "UseCardCoreTests", dependencies: ["UseCardCore"])
    ],
    swiftLanguageModes: [.v5]
)
