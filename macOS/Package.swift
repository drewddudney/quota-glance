// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QuotaGlance",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "QuotaGlance", targets: ["QuotaGlance"])],
    targets: [
        .executableTarget(
            name: "QuotaGlance",
            path: "Sources/QuotaGlance"
        ),
        .testTarget(
            name: "QuotaGlanceTests",
            dependencies: ["QuotaGlance"],
            path: "Tests/QuotaGlanceTests"
        )
    ]
)
