// swift-tools-version:5.9
import PackageDescription

// Hedef klasörleri SwiftPM varsayılanlarından alınır:
//   Plan      -> Sources/Plan
//   PlanTests -> Tests/PlanTests
let package = Package(
    name: "Plan",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Plan"),
        .testTarget(name: "PlanTests", dependencies: ["Plan"])
    ]
)
