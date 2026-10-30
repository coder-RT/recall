// swift-tools-version: 6.0
// RecallKit: all of the iPhone app's real logic. Targets list their dependencies explicitly, so a forbidden import
// fails to compile (apps/ios/ARCHITECTURE.md §3). Only Apple packages are used (the OpenAPI generator and runtime).
import PackageDescription

let package = Package(
    name: "RecallKit",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "RecallDomain", targets: ["RecallDomain"]),
        .library(name: "RecallCapture", targets: ["RecallCapture"]),
        .library(name: "RecallUpload", targets: ["RecallUpload"]),
        .library(name: "RecallNetworking", targets: ["RecallNetworking"]),
        .library(name: "RecallVoice", targets: ["RecallVoice"]),
        .library(name: "RecallDesign", targets: ["RecallDesign"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
    ],
    targets: [
        .target(name: "RecallDomain"),
        .target(name: "RecallCapture", dependencies: ["RecallDomain"]),
        .target(name: "RecallNetworking", dependencies: [
            "RecallDomain",
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
        ], plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]),
        .target(name: "RecallUpload", dependencies: ["RecallDomain", "RecallNetworking"]),
        .target(name: "RecallVoice", dependencies: ["RecallDomain"]),
        .target(name: "RecallDesign", dependencies: ["RecallDomain"]),
        .testTarget(name: "RecallDomainTests", dependencies: ["RecallDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
