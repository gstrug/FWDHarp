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
                "Bridge",
                "FWDHarp.entitlements",
                "Info.plist",
                "PrivacyInfo.xcprivacy",
                "FWDHarpApp.swift",
                "ContentView.swift",
                "Views",
                "Store/InstrumentStore.swift",
                "Store/HarpPlayer.swift",
                "Store/LevelMeters.swift",
                "Store/CPUMonitor.swift",
                // App bundle resources, loaded through Bundle.main; the core has no use
                // for them and SwiftPM warns if they are neither declared nor excluded.
                "Resources",
                "Engine/AudioEngineManager.swift",
                "Engine/AudioLevel.swift",
                "Engine/PluginManager.swift",
                "Engine/MIDIInputManager.swift",
                "Engine/AutoStrummer.swift",
                "Engine/MIDIOutput.swift",
                "Engine/NoteRouter.swift"
            ],
            sources: [
                "Models/Harmony.swift",
                "Models/PluginInfo.swift",
                "Models/GeneralMIDI.swift",
                "Engine/PluginLoadTracker.swift",
                "Models/HarpSetup.swift",
                "Models/MIDIMessage.swift",
                "Models/Pads.swift",
                "Models/AutoStrum.swift",
                "Models/MIDIOut.swift",
                "Models/StrumPlate.swift",
                "Store/SetupStorage.swift"
            ]
        ),
        .testTarget(
            name: "FWDHarpCoreTests",
            dependencies: ["FWDHarpCore"],
            path: "Tests/FWDHarpCoreTests"
        )
    ]
)
