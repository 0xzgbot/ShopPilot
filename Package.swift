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
            name: "ShopPilotVerify0800",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0800"
        ),
        .executableTarget(
            name: "ShopPilotVerify0801",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0801"
        ),
        .executableTarget(
            name: "ShopPilotVerify0803",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0803"
        ),
        .executableTarget(
            name: "ShopPilotVerify0804",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0804"
        ),
        .executableTarget(
            name: "ShopPilotVerify0805",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0805"
        ),
        .executableTarget(
            name: "ShopPilotVerify0806",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0806"
        ),
        .executableTarget(
            name: "ShopPilotVerify0807",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0807"
        ),
        .executableTarget(
            name: "ShopPilotVerify0808",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0808"
        ),
        .executableTarget(
            name: "ShopPilotVerify0903",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0903"
        ),
        .executableTarget(
            name: "ShopPilotVerify0902",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0902"
        ),
        .executableTarget(
            name: "ShopPilotVerify0908",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0908"
        ),
        .executableTarget(
            name: "ShopPilotVerify0909",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0909"
        ),
        .executableTarget(
            name: "ShopPilotVerify1000",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1000"
        ),
        .executableTarget(
            name: "ShopPilotVerify1001",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1001"
        ),
        .executableTarget(
            name: "ShopPilotVerify1003",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1003"
        ),
        .executableTarget(
            name: "ShopPilotVerify1006",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1006"
        ),
        .executableTarget(
            name: "ShopPilotVerify1008",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1008"
        ),
        .executableTarget(
            name: "ShopPilotVerify1010",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1010"
        ),
        .executableTarget(
            name: "ShopPilotVerifyPluginABI",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyPluginABI"
        ),
        .executableTarget(
            name: "ShopPilotVerify1207",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1207"
        ),
        .executableTarget(
            name: "ShopPilotVerify1209",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1209"
        ),
        .executableTarget(
            name: "ShopPilotVerify1206",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1206"
        ),
        .executableTarget(
            name: "ShopPilotVerify1204",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1204"
        ),
        .executableTarget(
            name: "ShopPilotVerify1201",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1201"
        ),
        .executableTarget(
            name: "ShopPilotVerify1202",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1202"
        ),
        .executableTarget(
            name: "ShopPilotVerify1205",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1205"
        ),
        .executableTarget(
            name: "ShopPilotVerify1203",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1203"
        ),
        .executableTarget(
            name: "ShopPilotVerify1208",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1208"
        ),
        .executableTarget(
            name: "ShopPilotVerify1210",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1210"
        ),
        .executableTarget(
            name: "ShopPilotVerify1301",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1301"
        ),
        .executableTarget(
            name: "ShopPilotVerify1302",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1302"
        ),
        .executableTarget(
            name: "ShopPilotVerify1303",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1303"
        ),
        .executableTarget(
            name: "ShopPilotVerify1304",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1304"
        ),
        .executableTarget(
            name: "ShopPilotVerify1305",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1305"
        ),
        .executableTarget(
            name: "ShopPilotVerify1311",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1311"
        ),
        .executableTarget(
            name: "ShopPilotVerify1312",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1312"
        ),
        .executableTarget(
            name: "ShopPilotVerify1313",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1313"
        ),
        .executableTarget(
            name: "ShopPilotVerify1910a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1910a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1910b",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1910b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1900a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1900a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1900e",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1900e"
        ),
        .executableTarget(
            name: "ShopPilotVerify1900f",
            dependencies: ["ShopPilotGeometry", "ShopPilotCore"],
            path: "Sources/ShopPilotVerify1900f"
        ),
        .executableTarget(
            name: "ShopPilotVerify1900b",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1900b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1314",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1314"
        ),
        .executableTarget(
            name: "ShopPilotVerify1315",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1315"
        ),
        .executableTarget(
            name: "ShopPilotVerify1316",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1316"
        ),
        .executableTarget(
            name: "ShopPilotVerify1317",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1317"
        ),
        .executableTarget(
            name: "ShopPilotVerify1319",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1319"
        ),
        .executableTarget(
            name: "ShopPilotVerify1320",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1320"
        ),
        .executableTarget(
            name: "ShopPilotVerify1321",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1321"
        ),
        .executableTarget(
            name: "ShopPilotVerify1322",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1322"
        ),
        .executableTarget(
            name: "ShopPilotVerify1323",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1323"
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
            name: "ShopPilotVerify0215",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0215"
        ),
        .executableTarget(
            name: "ShopPilotVerify0214",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0214"
        ),
        .executableTarget(
            name: "ShopPilotVerifyGadget",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyGadget"
        ),
        .executableTarget(
            name: "ShopPilotVerifyStudio",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyStudio"
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
            name: "ShopPilotVerifyBitmapHF",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyBitmapHF"
        ),
        .executableTarget(
            name: "ShopPilotVerifySpecialty",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifySpecialty"
        ),
        .executableTarget(
            name: "ShopPilotVerifySculpt",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifySculpt"
        ),
        .executableTarget(
            name: "ShopPilotVerifyInlayRecipe",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyInlayRecipe"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDragKnife",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyDragKnife"
        ),
        .executableTarget(
            name: "ShopPilotVerifyPhotoVCarve",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyPhotoVCarve"
        ),
        .executableTarget(
            name: "ShopPilotVerifyTexture",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyTexture"
        ),
        .executableTarget(
            name: "ShopPilotVerifySketchCarve",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifySketchCarve"
        ),
        .executableTarget(
            name: "ShopPilotVerifyCombine",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyCombine"
        ),
        .executableTarget(
            name: "ShopPilotVerifyRotaryWrap",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyRotaryWrap"
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
            name: "ShopPilotVerifyUI609",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyUI609"
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
            name: "ShopPilotTestPackGen",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotTestPackGen"
        ),
        .executableTarget(
            name: "ShopPilotVerifyTestPack",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyTestPack"
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
            name: "ShopPilotVerifySHAKEf",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifySHAKEf"
        ),
        .executableTarget(
            name: "ShopPilotVerifySHAKEg",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifySHAKEg"
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
            name: "ShopPilotVerify0705",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0705"
        ),

        .executableTarget(
            name: "ShopPilotVerify0707",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0707"
        ),

        .executableTarget(
            name: "ShopPilotVerify0708",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0708"
        ),

        .executableTarget(
            name: "ShopPilotVerify0711",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0711"
        ),

        .executableTarget(
            name: "ShopPilotVerify0715",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0715"
        ),

        .executableTarget(
            name: "ShopPilotVerify0710",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0710"
        ),

        .executableTarget(
            name: "ShopPilotVerify0906",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0906"
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

        .executableTarget(
            name: "ShopPilotVerifyUXPolish",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyUXPolish"
        ),

        .executableTarget(
            name: "ShopPilotVerifyOBJImport",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyOBJImport"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDWGImport",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyDWGImport"
        ),

        .executableTarget(
            name: "ShopPilotVerify1134",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1134"
        ),
        .executableTarget(
            name: "ShopPilotVerifyFitCurves",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyFitCurves"
        ),
        .executableTarget(
            name: "ShopPilotVerifyModelOffset",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyModelOffset"
        ),
        .executableTarget(
            name: "ShopPilotVerifyWrappedFluting",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyWrappedFluting"
        ),
        .executableTarget(
            name: "ShopPilotVerify1135",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1135"
        ),
        .executableTarget(
            name: "ShopPilotVerify0209",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0209"
        ),
        .executableTarget(
            name: "ShopPilotVerify0216",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0216"
        ),
        .executableTarget(
            name: "ShopPilotVerify0316",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0316"
        ),
        .executableTarget(
            name: "ShopPilotVerify0315",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0315"
        ),
        .executableTarget(
            name: "ShopPilotVerify0512",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify0512"
        ),
        .executableTarget(
            name: "ShopPilotVerifyEPSImport",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyEPSImport"
        ),
        .executableTarget(
            name: "ShopPilotVerify3MFImport",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify3MFImport"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDrillBank",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyDrillBank"
        ),

        .executableTarget(
            name: "ShopPilotVerifyDynamicProps",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyDynamicProps"
        ),

        .executableTarget(
            name: "ShopPilotVerifyShapeTools",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyShapeTools"
        ),

        .executableTarget(
            name: "ShopPilotVerifyComponentOps",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyComponentOps"
        ),

        .executableTarget(
            name: "ShopPilotVerifySweep",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifySweep"
        ),

        .executableTarget(
            name: "ShopPilotVerify0704",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify0704"
        ),

        .executableTarget(
            name: "ShopPilotVerifyPDFImport",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyPDFImport"
        ),

        .executableTarget(
            name: "ShopPilotVerifyAIImport",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyAIImport"
        ),

        // Phase O Wave 0 (2026-08-12) — pre-registered so worktree agents
        // never touch Package.swift; they fill the stub mains only.
        .executableTarget(
            name: "ShopPilotVerify1401b",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1401b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1401d",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1401d"
        ),
        .executableTarget(
            name: "ShopPilotVerify1400a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1400a"
        ),

        // Phase O Wave 1 (2026-08-12) — config reaches open, friendly copy,
        // Autosaver wiring, Metal honesty.
        .executableTarget(
            name: "ShopPilotVerify1401a",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1401a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1400c",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1400c"
        ),
        .executableTarget(
            name: "ShopPilotVerify1402a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1402a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1402c",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1402c"
        ),

        // Phase O Wave 2 (2026-08-12) — jog newline+G90, status poll,
        // corrupt sheets, coach tip card.
        .executableTarget(
            name: "ShopPilotVerify1401c",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1401c"
        ),
        .executableTarget(
            name: "ShopPilotVerify1401f",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1401f"
        ),
        .executableTarget(
            name: "ShopPilotVerify1402b",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1402b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1400f",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1400f"
        ),

        // Phase O Wave 3 (2026-08-12) — single realtime writer, inspector
        // honesty.
        .executableTarget(
            name: "ShopPilotVerify1401e",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1401e"
        ),
        .executableTarget(
            name: "ShopPilotVerify1400g",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1400g"
        ),

        // Phase O follow-up (2026-08-12) — coach tip-card actions on catalog
        // rules (SPK-1400j).
        .executableTarget(
            name: "ShopPilotVerify1400j",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1400j"
        ),

        // Phase O follow-up (2026-08-12) — custom baud via IOSSIOSPEED
        // (SPK-1401g) and serialized writes (SPK-1401h).
        .executableTarget(
            name: "ShopPilotVerify1401g",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1401g"
        ),
        .executableTarget(
            name: "ShopPilotVerify1401h",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1401h"
        ),

        // Phase P (2026-08-12) — stream hygiene + coach + factory.
        .executableTarget(
            name: "ShopPilotVerify1504",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1504"
        ),
        .executableTarget(
            name: "ShopPilotVerify1508",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1508"
        ),
        .executableTarget(
            name: "ShopPilotVerify1502",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1502"
        ),
        .executableTarget(
            name: "ShopPilotVerify1509",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1509"
        ),
        .executableTarget(
            name: "ShopPilotVerify1501",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1501"
        ),
        .executableTarget(
            name: "ShopPilotVerify1506",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1506"
        ),

        // Phase Q (2026-08-12) — Home uses $H, not G28.
        .executableTarget(
            name: "ShopPilotVerify1608",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1608"
        ),
        .executableTarget(
            name: "ShopPilotVerify1609",
            dependencies: ["ShopPilotCore", "ShopPilotSerial"],
            path: "Sources/ShopPilotVerify1609"
        ),

        // AppSession split slices (2026-08-12) — sample-load (1403a), undo
        // stack (1403b), profile generate (1403c), machine facade (1403d).
        .executableTarget(
            name: "ShopPilotVerify1403a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1403a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1403b",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1403b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1403c",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerify1403c"
        ),
        .executableTarget(
            name: "ShopPilotVerify1403d",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1403d"
        ),
        .executableTarget(
            name: "ShopPilotVerifyBUG03",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyBUG03"
        ),
        .executableTarget(
            name: "ShopPilotVerify1700a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1700a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1700b",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1700b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1700c",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1700c"
        ),
        .executableTarget(
            name: "ShopPilotVerify1800a",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1800a"
        ),
        .executableTarget(
            name: "ShopPilotVerify1800b",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1800b"
        ),
        .executableTarget(
            name: "ShopPilotVerify1800c",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1800c"
        ),
        .executableTarget(
            name: "ShopPilotVerify1800d",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1800d"
        ),
        .executableTarget(
            name: "ShopPilotVerify1800e",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1800e"
        ),
        .executableTarget(
            name: "ShopPilotVerify1800g",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1800g"
        ),
        .executableTarget(
            name: "ShopPilotVerify1800h",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1800h"
        ),
        .executableTarget(
            name: "ShopPilotVerify1800f",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerify1800f"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDOGFOOD02",
            dependencies: ["ShopPilotCore", "ShopPilot"],
            path: "Sources/ShopPilotVerifyDOGFOOD02"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDOGFOOD02b",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyDOGFOOD02b"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDOGFOOD01",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyDOGFOOD01"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDOGFOOD03",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyDOGFOOD03"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDOGFOOD1920d",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyDOGFOOD1920d"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDOGFOOD1920e",
            dependencies: ["ShopPilotCore", "ShopPilotGeometry"],
            path: "Sources/ShopPilotVerifyDOGFOOD1920e"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDOGFOOD1920f",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyDOGFOOD1920f"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDOGFOOD1920g",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyDOGFOOD1920g"
        ),
        .executableTarget(
            name: "ShopPilotVerifyDOGFOOD1920h",
            dependencies: ["ShopPilotCore"],
            path: "Sources/ShopPilotVerifyDOGFOOD1920h"
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
            path: "Sources/ShopPilotGeometry",
            linkerSettings: [
                .linkedLibrary("z")
            ]
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
