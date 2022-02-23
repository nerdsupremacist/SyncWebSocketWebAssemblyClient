// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SyncWebSocketWebAssemblyClient",
    platforms: [.macOS(.v11), .iOS(.v14), .watchOS(.v6), .tvOS(.v14)],
    products: [
        .library(
            name: "SyncWebSocketWebAssemblyClient",
            targets: ["SyncWebSocketWebAssemblyClient"]),
    ],
    dependencies: [
        .package(name: "Sync", url: "https://github.com/nerdsupremacist/Sync.git", from: "1.0.2"),
        .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", .upToNextMinor(from: "0.12.0")),
    ],
    targets: [
        .target(
            name: "SyncWebSocketWebAssemblyClient",
            dependencies: [
                "Sync",
                .product(
                    name: "JavaScriptKit",
                    package: "JavaScriptKit",
                    condition: .when(platforms: [.wasi])
                ),
            ]),
        .testTarget(
            name: "SyncWebSocketWebAssemblyClientTests",
            dependencies: ["SyncWebSocketWebAssemblyClient"]),
    ]
)
