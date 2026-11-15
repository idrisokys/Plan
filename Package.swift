// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "NotMenu",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "NotMenu", path: "Sources/NotMenu")]
)
