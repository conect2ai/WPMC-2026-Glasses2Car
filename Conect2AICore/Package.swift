// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Conect2AICore",
    platforms: [.iOS(.v15), .macOS(.v13)],
    products: [
        .library(name: "Conect2AICore", targets: ["Conect2AICore"])
    ],
    targets: [
        .target(name: "Conect2AICore"),
        .testTarget(
            name: "Conect2AICoreTests",
            dependencies: ["Conect2AICore"]
        ),
    ]
)
