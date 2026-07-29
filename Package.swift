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
            path: "Sources/ShopPilotGeometry"
        ),
        .testTarget(
            name: "ShopPilotTests",
            dependencies: [
                "ShopPilot",
                "ShopPilotCore",
                "ShopPilotSerial",
                "ShopPilotGeometry"
            ],
            path: "Tests/ShopPilotTests"
        )
    ]
)
