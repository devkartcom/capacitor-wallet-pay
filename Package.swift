// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DevkartcomCapacitorWalletPay",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "DevkartcomCapacitorWalletPay", targets: ["DevkartcomCapacitorWalletPay"])
    ],
    dependencies: [
        .package(
            url: "https://github.com/ionic-team/capacitor-swift-pm.git",
            exact: "8.5.2"
        )
    ],
    targets: [
        .target(
            name: "DevkartcomCapacitorWalletPay",
            dependencies: [
                .product(name: "Capacitor", package: "capacitor-swift-pm"),
                .product(name: "Cordova", package: "capacitor-swift-pm")
            ],
            path: "ios/Plugin"
        )
    ]
)
