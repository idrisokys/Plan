// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Plan",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Plan", path: "Sources/Plan"),
        .testTarget(name: "PlanTests", dependencies: ["Plan"], path: "Tests/PlanTests")
    ]
)
