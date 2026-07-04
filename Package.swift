// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "QuotaRadar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "QuotaRadar", targets: ["QuotaRadar"])
    ],
    targets: [
        .executableTarget(
            name: "QuotaRadar",
            path: "Sources/QuotaRadar",
            resources: [
                .copy("Resources/AppIcon.png")
            ]
        ),
        .testTarget(
            name: "QuotaRadarTests",
            dependencies: ["QuotaRadar"],
            path: "tests/QuotaRadarTests"
        )
    ]
)
