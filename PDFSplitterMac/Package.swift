// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PDFSplitterMac",
    platforms: [
        .macOS(.v12),
    ],
    products: [
        .executable(
            name: "PDFSplitterMac",
            targets: ["PDFSplitterMac"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "PDFSplitterMac"
        ),
    ]
)
