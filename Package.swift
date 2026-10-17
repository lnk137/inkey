// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "inkey",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Inkey", targets: ["Inkey"])],
    targets: [
        .executableTarget(name: "Inkey"),
        .testTarget(name: "InkeyTests", dependencies: ["Inkey"])
    ],
    swiftLanguageModes: [.v5]
)
