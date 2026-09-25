// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FilmSimCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FilmSimCore", targets: ["FilmSimCore"]),
    ],
    targets: [
        .target(name: "FilmSimCore"),
        .testTarget(name: "FilmSimCoreTests", dependencies: ["FilmSimCore"]),
    ]
)
