// swift-tools-version: 6.0
import PackageDescription
import Foundation

let nativeLibraryPath = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("third_party/mirrordeck-airplay/native/build").path

let package = Package(
    name: "iphone-use",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "iphone-use", targets: ["iPhoneUse"])
    ],
    targets: [
        .testTarget(name: "iPhoneUseTests", dependencies: ["iPhoneUse"], path: "Tests", linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", nativeLibraryPath])]),
        .target(name: "CMirrorBridge", path: "Sources/CMirrorBridge", publicHeadersPath: "include"),
        .executableTarget(
            name: "iPhoneUse",
            dependencies: ["CMirrorBridge"],
            path: "Sources/iPhoneUse",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-Lthird_party/mirrordeck-airplay/native/build", "-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedLibrary("MirrorCore"), .linkedFramework("VideoToolbox")
            ]
        )
    ]
)
