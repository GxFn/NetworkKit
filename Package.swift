// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AOXNetworkKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "AOXNetworkKit", targets: ["AOXNetworkKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "5.9.0"),
    ],
    targets: [
        .target(
            name: "AOXNetworkKit",
            dependencies: ["Alamofire"]
        ),
    ]
)
