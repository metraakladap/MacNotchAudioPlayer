// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MacNotchPlayer",
    platforms: [
        .macOS(.v26)
    ],
    dependencies: [
        .package(path: "vendor/DynamicNotchKit")
    ],
    targets: [
        .executableTarget(
            name: "MacNotchPlayer",
            dependencies: ["DynamicNotchKit"],
            path: "Sources/MacNotchPlayer",
            swiftSettings: [
                // Relaxed concurrency: the now-playing stream reader hops to the
                // main actor explicitly, so Swift 5 mode keeps the code simple.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
