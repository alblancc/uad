// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "UniversalAI_Developer",
    dependencies: [
        .package(url: "https://github.com/MacPaw/OpenAI.git", branch: "main")
    ],
    targets: [
        .executableTarget(
            name: "UniversalAI_Developer",
            dependencies: ["OpenAI"]),
        .testTarget(
            name: "UniversalAI_DeveloperTests",
            dependencies: ["UniversalAI_Developer"]),
    ]
)
