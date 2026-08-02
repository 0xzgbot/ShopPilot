// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShopPilot",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "ShopPilot",
            dependencies: ["ShopPilotCore", "ShopPilotSerial", "ShopPilotGeometry"],
            path: "Sources/ShopPilot"
        ),
        .executableTarget(
            name: "ShopPilotGoldenPath",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotGoldenPath"
        ),
        .executableTarget(
            name: "ShopPilotVerify1100",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1100"
        ),
        .executableTarget(
            name: "ShopPilotVerify1103a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1103a"
        ),
        .target(
            name: "ShopPilotCore",
            path: "Sources/ShopPilotCore"
        ),
        .target(
            name: "ShopPilotSerial",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotSerial"
        ),
        .target(
            name: "ShopPilotGeometry",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotGeometry"
        ),
        .testTarget(
            name: "ShopPilotTests",
            dependencies: [
                "ShopPilotCore",
                "ShopPilotSerial",
                "ShopPilotGeometry"
            ],
            path: "Tests/ShopPilotTests",
            exclude: ["AppSessionTests.swift.pending"]
        )
    ]
)
