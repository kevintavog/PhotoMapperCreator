// swift-tools-version:3.1

import PackageDescription

let package = Package(
    name: "PhotoMapCreator",
    dependencies: [
        .Package(url: "https://github.com/johnsundell/files.git", majorVersion: 1),
        .Package(url: "https://github.com/johnsundell/wrap.git", majorVersion: 2),
        .Package(url: "https://github.com/johnsundell/unbox.git", majorVersion: 2),
        .Package(url: "https://github.com/jakeheis/SwiftCLI", majorVersion: 3),
        .Package(url: "https://github.com/duemunk/Async", majorVersion: 2),
        .Package(url: "https://github.com/jakeheis/Spawn", majorVersion: 0)
    ]
)
