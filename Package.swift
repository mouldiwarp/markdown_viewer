// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MarkdownViewerNative",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MarkdownViewerNative", targets: ["MarkdownViewerNative"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "MarkdownViewerNative",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown"),
            ]
        )
    ]
)
