// swift-tools-version: 5.9
import PackageDescription

// Portable computation engine + tests. The macOS SwiftUI app itself is in TradePlanner.xcodeproj.
let package = Package(
    name: "TradeCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "TradeCore", targets: ["TradeCore"])],
    targets: [
        .target(name: "TradeCore", path: "TradePlanner/Core"),
        .testTarget(name: "TradeCoreTests", dependencies: ["TradeCore"], path: "Tests/TradeCoreTests")
    ]
)
