// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-xtend",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(
            name: "Xtend",
            targets: ["Xtend"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/mipalgu/swift-ecore", branch: "release/0.8"),
    ],
    targets: [
        .target(
            name: "Xtend",
            dependencies: [
                .product(name: "ECore", package: "swift-ecore"),
                .product(name: "EMFBase", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "XtendTests",
            dependencies: [
                "Xtend",
                .product(name: "ECore", package: "swift-ecore"),
                .product(name: "EMFBase", package: "swift-ecore"),
            ],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
    ]
)
