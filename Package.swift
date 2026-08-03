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
            name: "ShopPilotVerify0314a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0314a"
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
        .executableTarget(
            name: "ShopPilotVerify1125",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1125"
        ),
        .executableTarget(
            name: "ShopPilotVerify1120",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1120"
        ),
        .executableTarget(
            name: "ShopPilotVerify1130",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1130"
        ),
        .executableTarget(
            name: "ShopPilotVerify1123",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1123"
        ),
        .executableTarget(
            name: "ShopPilotVerify1132",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1132"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101b",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101i",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101i"
        ),
        .executableTarget(
            name: "ShopPilotVerify1131",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1131"
        ),
        .executableTarget(
            name: "ShopPilotVerifyProfileToolpath",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyProfileToolpath"
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
