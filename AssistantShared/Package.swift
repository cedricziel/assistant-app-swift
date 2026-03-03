// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AssistantShared",
    platforms: [
        .iOS("26.2"),
        .macOS("26.2"),
    ],
    products: [
        .library(
            name: "AssistantShared",
            targets: ["AssistantShared"],
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/MacPaw/OpenAI.git", from: "0.4.7"),
    ],
    targets: [
        .target(
            name: "AssistantShared",
            dependencies: [
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "OpenAI", package: "OpenAI"),
            ],
        ),
    ],
)
