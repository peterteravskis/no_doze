// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "NoDoze",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NoDoze", targets: ["NoDoze"])
    ],
    targets: [
        .executableTarget(name: "NoDoze")
    ]
)
