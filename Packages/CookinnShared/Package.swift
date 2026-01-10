// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CookinnShared",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "CookinnShared", targets: ["CookinnShared"])
    ],
    targets: [
        .target(
            name: "CookinnShared",
            path: "Sources/CookinnShared"
        )
    ]
)
