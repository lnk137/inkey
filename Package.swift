// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "inkey",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Inkey", targets: ["Inkey"])],
    targets: [
        .executableTarget(name: "Inkey", resources: [.process("Resources")]),
        .testTarget(name: "InkeyTests", dependencies: ["Inkey"])
    ],
    swiftLanguageModes: [.v5]
)
