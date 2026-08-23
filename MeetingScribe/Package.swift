// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MeetingScribe",
    platforms: [
        // 14.2, not just 14.0 — the Core Audio process-tap APIs used for
        // system audio capture (AudioHardwareCreateProcessTap etc.) only
        // exist from 14.2 onward.
        .macOS("14.2")
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        // OpenCC: converts Whisper's mixed Simplified/Traditional output to
        // Hong Kong-standard Traditional Chinese.
        .package(url: "https://github.com/ddddxxx/SwiftyOpenCC.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingScribe",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "OpenCC", package: "SwiftyOpenCC"),
            ],
            path: "Sources/MeetingScribe"
        )
    ]
)
