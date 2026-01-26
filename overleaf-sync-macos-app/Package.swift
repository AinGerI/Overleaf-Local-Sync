// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "OverleafSyncMacApp",
  platforms: [
    .macOS(.v13),
  ],
  products: [
    .executable(
      name: "OverleafSyncMacApp",
      targets: ["OverleafSyncMacApp"]
    ),
  ],
  targets: [
    .executableTarget(
      name: "OverleafSyncMacApp"
    ),
    .testTarget(
      name: "OverleafSyncMacAppTests",
      dependencies: ["OverleafSyncMacApp"]
    ),
  ]
)

