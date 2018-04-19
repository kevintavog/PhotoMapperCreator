// swift-tools-version:4.0

import PackageDescription

let package = Package(
    name: "PhotoMapCreator",
    dependencies: [
        .package(url: "https://github.com/johnsundell/files.git", from: "2.2.1"),
        .package(url: "https://github.com/johnsundell/wrap.git", from: "3.0.1"),
        .package(url: "https://github.com/johnsundell/unbox.git", from: "2.5.0"),
        .package(url: "https://github.com/jakeheis/SwiftCLI", from: "4.3.2"),
        .package(url: "https://github.com/duemunk/Async", from: "2.0.4"),
        .package(url: "https://github.com/jakeheis/Spawn", from: "0.0.6"),
        .package(url: "https://github.com/Alamofire/Alamofire.git", from: "4.7.2")
    ],
    targets: [
        .target(
            name: "PhotoMapCreator",
            dependencies: ["Files", "Wrap", "Unbox", "SwiftCLI", "Async", "Spawn", "Alamofire"]),
    ]
)
