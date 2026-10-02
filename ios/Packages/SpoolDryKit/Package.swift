// swift-tools-version: 5.9
// SpoolDryKit: platform-independent core of the SpoolDry app (BLE protocol v1 codec, filament
// knowledge base, drying-session tracking, free-tier policy). No UIKit/CoreBluetooth dependencies,
// so it is unit-tested with `swift test` on macOS (and Linux).
import PackageDescription

let package = Package(
    name: "SpoolDryKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SpoolDryKit", targets: ["SpoolDryKit"]),
    ],
    targets: [
        .target(name: "SpoolDryKit"),
        .testTarget(
            name: "SpoolDryKitTests",
            dependencies: ["SpoolDryKit"],
            resources: [.copy("Resources")]
        ),
    ]
)
