// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "IPADispatch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "IPADispatch",
            path: "Sources"
        )
    ],
    swiftLanguageVersions: [.v5]
)
