// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetworkKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "NetworkKit", targets: ["NetworkKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
    ],
    targets: [
        .target(
            name: "NetworkKit",
            dependencies: ["Alamofire"]
        ),
    ]
)
