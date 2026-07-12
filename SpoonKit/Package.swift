// swift-tools-version: 6.3

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableExperimentalFeature("Lifetimes"),
  .enableExperimentalFeature("Extern"),
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("InternalImportsByDefault"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("InferIsolatedConformances"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("ImmutableWeakCaptures"),
  .defaultIsolation(nil),
  .strictMemorySafety(),
  .treatAllWarnings(as: .error)
]

let package = Package(
  name: "SpoonKit",
  defaultLocalization: "en",
  platforms: [
    .macOS(.v26),
  ],
  products: [
    .library(name: "SpoonIntent", targets: ["SpoonIntent"]),
    .library(name: "SpoonUI", targets: ["SpoonUI"])
  ],
  dependencies: [
    .package(url: "https://github.com/square/Valet.git", from: "5.0.0"),
    .package(url: "https://github.com/sindresorhus/Defaults.git", from: "9.0.0"),
    .package(url: "https://github.com/gohanlon/swift-memberwise-init-macro.git", from: "0.6.0"),
    .package(url: "https://github.com/vapor/multipart-kit.git", exact: "5.0.0-alpha.5"),
    .package(url: "https://github.com/apple/swift-http-types.git", from: "1.0.0"),
    .package(url: "https://github.com/swiftlang/swift-subprocess.git", from: "1.0.0-beta.1"),
    .package(url: "https://github.com/apple/swift-async-algorithms.git", from: "1.0.0"),
  ],
  targets: [
    .target(
      name: "SpoonCore",
      dependencies: [
        .product(name: "MemberwiseInit", package: "swift-memberwise-init-macro"),
        .product(name: "Valet", package: "Valet"),
        .product(name: "Defaults", package: "Defaults"),
        .product(name: "DefaultsMacros", package: "Defaults"),
        .product(name: "MultipartKit", package: "multipart-kit"),
        .product(name: "HTTPTypes", package: "swift-http-types"),
        .product(name: "HTTPTypesFoundation", package: "swift-http-types"),
        .product(name: "Subprocess", package: "swift-subprocess"),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "SpoonCoreTests",
      dependencies: ["SpoonCore"],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "SpoonIntent",
      dependencies: [
        .target(name: "SpoonCore"),
      ],
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "SpoonIntentTests",
      dependencies: [
        .target(name: "SpoonIntent"),
        .target(name: "SpoonCore"),
      ],
      swiftSettings: swiftSettings
    ),
    .target(
      name: "SpoonUI",
      dependencies: [
        .target(name: "SpoonCore"),
      ],
      swiftSettings: swiftSettings
    ),
  ]
)
