// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "LogFilterWasm",
  dependencies: [
    .package(url: "https://github.com/realm/SwiftLint", from: "0.58.2"),
    .package(url: "https://github.com/swiftwasm/WasmKit", from: "0.1.5"),
  ],
  targets: [
    .executableTarget(
      name: "LogFilterWasm",
      dependencies: [
        .product(name: "WasmKit", package: "WasmKit"),
        .product(name: "WasmParser", package: "WasmKit"),
        .product(name: "WAT", package: "WasmKit"),
      ],
      swiftSettings: [
        .unsafeFlags(
          ["-cross-module-optimization"],
          .when(configuration: .release)
        )
      ]
    )
  ]
)
