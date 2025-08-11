// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIConversationSDK",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "AIConversationSDK",
            targets: ["AIConversationSDK"]
        ),
    ],
    dependencies: [
        // No external dependencies for now
    ],
    targets: [
        .target(
            name: "AIConversationSDK",
            dependencies: [],
            path: "Sources/AIConversationSDK"
        ),
        .testTarget(
            name: "AIConversationSDKTests",
            dependencies: ["AIConversationSDK"],
            path: "Tests/AIConversationSDKTests"
        ),
    ]
) 