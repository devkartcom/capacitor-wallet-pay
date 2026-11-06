// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aybinv7CapacitorWalletPay",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "Aybinv7CapacitorWalletPay", targets: ["Aybinv7CapacitorWalletPay"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/ionic-team/capacitor-swift-pm.git",
            exact: "8.5.2"
        )
    ],
    targets: [
        .target(
            name: "Aybinv7CapacitorWalletPay",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Plugin"
        )
    ]
)
