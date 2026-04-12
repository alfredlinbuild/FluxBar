// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "FluxBar",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "FluxBar", targets: ["FluxBar"]),
    ],
    targets: [
        .executableTarget(
            name: "FluxBar"
        ),
    ],
    swiftLanguageModes: [.v6]
)
