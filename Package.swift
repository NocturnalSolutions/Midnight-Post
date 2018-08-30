// swift-tools-version:4.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Midnight Post",
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/IBM-Swift/Kitura.git", from: "2.4.0"),
        .package(url: "https://github.com/NocturnalSolutions/Swift-Kuery.git", .branch("alterable-pk")),
        .package(url: "https://github.com/NocturnalSolutions/Kitura-net.git", .branch("ClientRequest-Redirection")),
        .package(url: "https://github.com/NocturnalSolutions/Swift-Kuery-SQLite.git", .branch("alterable-pk")),
        .package(url: "https://github.com/IBM-Swift/Kitura-StencilTemplateEngine.git", from: "1.9.1"),
        .package(url: "https://github.com/IBM-Swift/Configuration.git", from: "3.0.1"),
        .package(url: "https://github.com/NocturnalSolutions/MidnightTest.git", .branch("master"))
        ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "Midnight Post",
            dependencies: ["MidnightPostApp"]
        ),
        .target(
            name: "MidnightPostApp",
            dependencies: ["Kitura", "SwiftKuerySQLite", "KituraStencil", "Configuration"]
        ),
        .testTarget(
            name: "MidnightPostTests",
            dependencies: ["MidnightPostApp", "MidnightTest"]
        )
    ]
)
