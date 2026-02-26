// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "loca",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "loca", targets: ["loca"]),
    ],
    targets: [
        .executableTarget(
            name: "loca",
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist",
                ]),
            ]
        ),
    ]
)
