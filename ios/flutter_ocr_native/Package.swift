// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "flutter_ocr_native",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "flutter-ocr-native", targets: ["flutter_ocr_native"]),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
    ],
    targets: [
        .target(
            name: "flutter_ocr_native",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
            ],
            path: "Sources/flutter_ocr_native"
        ),
    ]
)
