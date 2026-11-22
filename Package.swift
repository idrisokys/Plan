// swift-tools-version:6.2
import PackageDescription
import Foundation

// Hedef klasörleri:
//   CPlanCore -> Sources/CPlanCore (Rust çekirdeğinin C başlığı)
//   Plan      -> Sources/Plan      (menü çubuğu uygulaması, Notlarım)
//   PlanTests -> Tests/PlanTests
//
// CPU yoğun işler (tarama, arama, hash/metadata, küçük resim) rust/plan_core içindedir; paylaşım/eşitleme ise
// Android'le ORTAK qshare_core'dadır (plan_core'a statik olarak gömülür). Bunlar
// önce derlenmelidir: scripts/build_rust.sh  (build.sh ve CI bunu kendiliğinden çalıştırır).
//
// Plan'ın kodu Swift 5 dilinde yazıldı: swiftLanguageModes [.v5].
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let rustLibDir = "\(root)/rust/plan_core/target/aarch64-apple-darwin/release"

let package = Package(
    name: "Plan",
    platforms: [.macOS("14.6")],
    targets: [
        .target(name: "CPlanCore"),
        .executableTarget(
            name: "Plan",
            dependencies: ["CPlanCore"],
            linkerSettings: [.unsafeFlags(["-L", rustLibDir, "-lplan_core"])]
        ),
        .testTarget(
            name: "PlanTests",
            dependencies: ["Plan"],
            linkerSettings: [.unsafeFlags(["-L", rustLibDir, "-lplan_core"])]
        )
    ],
    swiftLanguageModes: [.v5]
)
