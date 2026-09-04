// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PomodoroIsland",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "PomodoroIsland",
            path: "Sources/PomodoroIsland"
        )
    ]
)
