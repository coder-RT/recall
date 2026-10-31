// swift-tools-version: 6.0
// RecallKit: all of the iPhone app's real logic. Targets list their dependencies explicitly, so a forbidden import
// fails to compile. Only Apple packages are used (the OpenAPI generator and runtime).
import PackageDescription

let package = Package(
    name: "RecallKit",
    platforms: [.iOS("26.0"), .macOS("15.0")],  // macOS only so `swift test` can check the pure targets on the Mac
    products: [
        .library(name: "RecallDomain", targets: ["RecallDomain"]),
        .library(name: "RecallCapture", targets: ["RecallCapture"]),
        .library(name: "RecallUpload", targets: ["RecallUpload"]),
        .library(name: "RecallNetworking", targets: ["RecallNetworking"]),
        .library(name: "RecallVoice", targets: ["RecallVoice"]),
        .library(name: "RecallDesign", targets: ["RecallDesign"]),
        .library(name: "RecallApplication", targets: ["RecallApplication"]),
        .library(name: "RecallPersistence", targets: ["RecallPersistence"]),
        .library(name: "RecallTestSupport", targets: ["RecallTestSupport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-http-types", from: "1.3.0"),
    ],
    targets: [
        .target(name: "RecallDomain"),
        // use cases: the domain's ports only, so no adapter (network, ARKit, files) can leak in
        .target(name: "RecallApplication", dependencies: ["RecallDomain"]),
        .target(name: "RecallPersistence", dependencies: ["RecallDomain"]),
        .target(name: "RecallTestSupport", dependencies: ["RecallDomain"]),
        .target(name: "RecallCapture", dependencies: ["RecallDomain"]),
        .target(name: "RecallNetworking", dependencies: [
            "RecallDomain",
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
        ], plugins: [.plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")]),
        .target(name: "RecallUpload", dependencies: ["RecallDomain"]),
        .target(name: "RecallVoice", dependencies: ["RecallDomain"]),
        .target(name: "RecallDesign", dependencies: ["RecallDomain"]),
        .testTarget(name: "RecallDomainTests", dependencies: ["RecallDomain"]),
        .testTarget(name: "RecallApplicationTests", dependencies: ["RecallApplication", "RecallTestSupport"]),
        .testTarget(name: "RecallPersistenceTests", dependencies: ["RecallPersistence"]),
        .testTarget(name: "RecallCaptureTests", dependencies: ["RecallCapture", "RecallDomain"]),
        .testTarget(name: "RecallNetworkingTests", dependencies: [
            "RecallNetworking", "RecallDomain",
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "HTTPTypes", package: "swift-http-types"),
        ]),
    ],
    swiftLanguageModes: [.v6]
)
