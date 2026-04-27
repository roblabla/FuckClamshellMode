// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "FuckClamshellMode",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "FuckClamshellMode",
            path: "Sources/FuckClamshellMode",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
