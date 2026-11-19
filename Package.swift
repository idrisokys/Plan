// swift-tools-version:6.2
import PackageDescription

// Hedef klasörleri:
//   Plan      -> Sources/Plan      (menü çubuğu uygulaması, Notlarım)
//   Filetor   -> Sources/Filetor   (dosya yöneticisi; Plan'ın bir parçası, kitaplık olarak derlenir)
//   PlanTests -> Tests/PlanTests
//
// Filetor Observation (@Observable) kullandığı için en düşük sistem macOS 14.6'dır.
// Plan'ın kodu Swift 5 dilinde yazıldı: swiftLanguageModes [.v5].
let package = Package(
    name: "Plan",
    platforms: [.macOS("14.6")],
    dependencies: [
        // Filetor: WebP'ye dönüştürme için
        .package(url: "https://github.com/SDWebImage/libwebp-Xcode", from: "1.6.0")
    ],
    targets: [
        .target(
            name: "Filetor",
            dependencies: [.product(name: "libwebp", package: "libwebp-Xcode")],
            exclude: ["LICENSE-Filetor"],
            swiftSettings: [
                // Filetor Xcode'da "Default Actor Isolation: MainActor" + "Approachable Concurrency" ile yazıldı
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("InferSendableFromCaptures"),
                .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
                .enableUpcomingFeature("DisableOutwardActorInference")
            ]
        ),
        .executableTarget(name: "Plan", dependencies: ["Filetor"]),
        .testTarget(name: "PlanTests", dependencies: ["Plan"])
    ],
    swiftLanguageModes: [.v5]
)
