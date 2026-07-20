// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "EnhaleCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14) // enables `swift test` from the command line, no Xcode required
    ],
    products: [
        .library(name: "EnhaleCore", targets: ["EnhaleCore"])
    ],
    targets: [
        .target(name: "EnhaleCore"),
        .testTarget(
            name: "EnhaleCoreTests",
            dependencies: ["EnhaleCore"]
        )
    ]
)
