// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Badger",
    products: [
        .library(name: "HabitStreakCore", targets: ["HabitStreakCore"]),
        .executable(name: "streakdemo", targets: ["StreakDemo"]),
    ],
    targets: [
        .target(
            name: "HabitStreakCore"
        ),
        .executableTarget(
            name: "StreakDemo",
            dependencies: ["HabitStreakCore"]
        ),
        .testTarget(
            name: "HabitStreakCoreTests",
            dependencies: ["HabitStreakCore"]
        ),
    ]
)
