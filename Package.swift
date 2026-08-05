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
            name: "ShopPilotVerify0312",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0312"
        ),
        .executableTarget(
            name: "ShopPilotVerify0308",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0308"
        ),
        .executableTarget(
            name: "ShopPilotVerify0318",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0318"
        ),
        .executableTarget(
            name: "ShopPilotVerify0210",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0210"
        ),
        .executableTarget(
            name: "ShopPilotVerify1100",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1100"
        ),
        .executableTarget(
            name: "ShopPilotVerify3Da",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify3Da"
        ),
        .executableTarget(
            name: "ShopPilotVerify3Db",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify3Db"
        ),
        .executableTarget(
            name: "ShopPilotVerify1103a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1103a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1103d",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1103d"
        ),
        .executableTarget(
            name: "ShopPilotVerify1103e",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1103e"
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
            name: "ShopPilotVerify1133",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1133"
        ),
        .executableTarget(
            name: "ShopPilotVerify1133b",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1133b"
        ),
        .executableTarget(
            name: "ShopPilotVerifyGolden25D",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyGolden25D"
        ),
        .executableTarget(
            name: "ShopPilotVerify3DGolden",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify3DGolden"
        ),
        .executableTarget(
            name: "ShopPilotVerify0211",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0211"
        ),
        .executableTarget(
            name: "ShopPilotVerify0603",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0603"
        ),
        .executableTarget(
            name: "ShopPilotVerify0604",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0604"
        ),
        .executableTarget(
            name: "ShopPilotVerifyUI601",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyUI601"
        ),
        .executableTarget(
            name: "ShopPilotVerify0319",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0319"
        ),
        .executableTarget(
            name: "ShopPilotVerify3DUI",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify3DUI"
        ),
        .executableTarget(
            name: "ShopPilotVerify3DRest",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify3DRest"
        ),
        .executableTarget(
            name: "ShopPilotVerify0415",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify0415"
        ),
        .executableTarget(
            name: "ShopPilotVerify0418",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0418"
        ),
        .executableTarget(
            name: "ShopPilotVerify1136a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1136a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1136b",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1136b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1136c",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1136c"
        ),
        .executableTarget(
            name: "ShopPilotVerify1136d",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1136d"
        ),
        .executableTarget(
            name: "ShopPilotVerifyVCarveClear",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyVCarveClear"
        ),
        .executableTarget(
            name: "ShopPilotVerify1137",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1137"
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

        .executableTarget(
            name: "ShopPilotVerify0201b",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0201b"
        ),
        .executableTarget(
            name: "ShopPilotVerify0203c",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0203c"
        ),
        .executableTarget(
            name: "ShopPilotVerify0310a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0310a"
        ),
        .executableTarget(
            name: "ShopPilotVerify0404a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0404a"
        ),
        .executableTarget(
            name: "ShopPilotVerify0404c",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0404c"
        ),
        .executableTarget(
            name: "ShopPilotVerify0412a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0412a"
        ),
        .executableTarget(
            name: "ShopPilotVerify0417a",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify0417a"
        ),
        .executableTarget(
            name: "ShopPilotVerify0500",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0500"
        ),
        .executableTarget(
            name: "ShopPilotVerify0600",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0600"
        ),
        .executableTarget(
            name: "ShopPilotFixtureGen",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotFixtureGen"
        ),
        .executableTarget(
            name: "ShopPilotVerifySHAKEd",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifySHAKEd"
        ),
        .executableTarget(
            name: "ShopPilotVerifySHAKEe",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifySHAKEe"
        ),
        .executableTarget(
            name: "ShopPilotVerify0601",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0601"
        ),
        .executableTarget(
            name: "ShopPilotVerifyFMR013",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyFMR013"
        ),
        .executableTarget(
            name: "ShopPilotVerifyFMR014",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerifyFMR014"
        ),
        .executableTarget(
            name: "ShopPilotVerifyFMR016",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerifyFMR016"
        ),
        .executableTarget(
            name: "ShopPilotVerifyFMR019",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyFMR019"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101FlipH",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101FlipH"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101d",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101d"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101e",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101e"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101g",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101g"
        ),
        .executableTarget(
            name: "ShopPilotVerify1106a",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1106a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1106b",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1106b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101f",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101f"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101h",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1101h"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101j",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101j"
        ),
        .executableTarget(
            name: "ShopPilotVerify1101k",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1101k"
        ),
        .executableTarget(
            name: "ShopPilotVerify1102c",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1102c"
        ),
        .executableTarget(
            name: "ShopPilotVerify1102d",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1102d"
        ),
        .executableTarget(
            name: "ShopPilotVerify1102g",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1102g"
        ),
        .executableTarget(
            name: "ShopPilotVerify1102e",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1102e"
        ),
        .executableTarget(
            name: "ShopPilotVerify1102f",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1102f"
        ),
        .executableTarget(
            name: "ShopPilotVerify1102h",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1102h"
        ),
        .executableTarget(
            name: "ShopPilotVerify1102i",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1102i"
        ),
        .executableTarget(
            name: "ShopPilotVerify1103",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1103"
        ),
        .executableTarget(
            name: "ShopPilotVerify1103c",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1103c"
        ),
        .executableTarget(
            name: "ShopPilotVerify1104",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1104"
        ),
        .executableTarget(
            name: "ShopPilotVerify1104a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1104a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1104b",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1104b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1104d",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1104d"
        ),
        .executableTarget(
            name: "ShopPilotVerify1104c",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1104c"
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
