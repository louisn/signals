// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SignalKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SignalKit", targets: ["SignalKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.0")
    ],
    targets: [
        .target(
            name: "SignalKit",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "SignalKitTests",
            dependencies: ["SignalKit"]
        )
    ]
)
