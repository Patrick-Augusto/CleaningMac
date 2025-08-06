
// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "CleanMyMacApp",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "CleanMyMacApp",
            targets: ["CleanMyMacApp"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "CleanMyMacApp",
            path: "CleanMyMacApp"
        )
    ]
)
