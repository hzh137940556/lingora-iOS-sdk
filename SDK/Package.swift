// swift-tools-version: 6.0
// 定义只包含可发布 SDK 与单元测试的 Lingora Swift Package。
import PackageDescription

let package = Package(
    name: "Lingora",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Lingora", targets: ["Lingora"]),
    ],
    targets: [
        .target(name: "Lingora"),
        .testTarget(name: "LingoraTests", dependencies: ["Lingora"]),
    ],
    swiftLanguageModes: [.v6]
)
