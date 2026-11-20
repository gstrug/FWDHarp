// swift-tools-version: 5.9
import PackageDescription

// The portable, tested core of FWD Harp: the music logic with no UI or audio, so
// `swift test` runs anywhere (GitHub runs it on every push). Add each new pure file to
// `sources`. Open FWDHarp.xcodeproj to work on the app, not this package.
let package = Package(
    name: "FWDHarpCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FWDHarpCore", targets: ["FWDHarpCore"])
    ],
    targets: [
        .target(
            name: "FWDHarpCore",
            path: "FWDHarp",
            exclude: [
                "Assets.xcassets",
                "FWDHarp.entitlements",
                "Info.plist",
                "FWDHarpApp.swift",
                "ContentView.swift"
            ],
            sources: [
                "Models/Harmony.swift"
            ]
        ),
        .testTarget(
            name: "FWDHarpCoreTests",
            dependencies: ["FWDHarpCore"],
            path: "Tests/FWDHarpCoreTests"
        )
    ]
)
