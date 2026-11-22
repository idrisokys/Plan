// swift-tools-version:6.2
import PackageDescription

// Hedef klasörleri:
//   Plan      -> Sources/Plan      (menü çubuğu uygulaması, Notlarım)
//   PlanTests -> Tests/PlanTests
//
// Plan'ın kodu Swift 5 dilinde yazıldı: swiftLanguageModes [.v5].
let package = Package(
    name: "Plan",
    platforms: [.macOS("14.6")],
    targets: [
        .executableTarget(name: "Plan"),
        .testTarget(name: "PlanTests", dependencies: ["Plan"])
    ],
    swiftLanguageModes: [.v5]
)
