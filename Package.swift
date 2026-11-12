// swift-tools-version: 5.9
import PackageDescription

// Portable computation engine + tests. The macOS SwiftUI app itself is in TradePlanner.xcodeproj.
let package = Package(
    name: "TradeCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TradeCore", targets: ["TradeCore"])],
    targets: [
        .target(
            name: "TradeCore",
            path: "TradePlanner",
            exclude: ["App", "Views"],
            sources: ["Core/TradeCalculator.swift", "Models/TradePlan.swift", "Models/PlanStore.swift"]
        ),
        .testTarget(name: "TradeCoreTests", dependencies: ["TradeCore"], path: "Tests/TradeCoreTests")
    ]
)
