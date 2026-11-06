// swift-tools-version: 6.0
import Foundation
import PackageDescription

// 仅有 Command Line Tools（未安装 Xcode）时，Swift Testing 的宏插件位于
// `.../host/plugins/testing/` 子目录，SwiftPM 默认不会加载，这里显式补上。
// 使用 Xcode 的工具链时该补丁自动失效。
let cltTestingPlugin = "/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
let hasXcode = FileManager.default.fileExists(atPath: "/Applications/Xcode.app")
let testingSwiftSettings: [SwiftSetting] = (hasXcode || !FileManager.default.fileExists(atPath: cltTestingPlugin))
    ? []
    : [.unsafeFlags(["-Xfrontend", "-load-plugin-library", "-Xfrontend", cltTestingPlugin])]

// Swift Package 只包含可独立编译的功能模块与测试；App 目标由 project.yml（XcodeGen）
// 编译 App/ 下的 SwiftUI 源码并链接这些模块。这样 `swift build` / `swift test` 可在
// 只安装 Command Line Tools 的机器上验证除 UI 外的全部逻辑。
let package = Package(
    name: "LingoLens",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "ModelRuntime", targets: ["ModelRuntime"]),
        .library(name: "ModelLibrary", targets: ["ModelLibrary"]),
        .library(name: "LLMClient", targets: ["LLMClient"]),
        .library(name: "Settings", targets: ["Settings"]),
        .library(name: "SelectionTranslate", targets: ["SelectionTranslate"]),
        .library(name: "SceneChat", targets: ["SceneChat"]),
        .library(name: "AudioCapture", targets: ["AudioCapture"]),
        .library(name: "Transcriber", targets: ["Transcriber"]),
        .library(name: "LiveSubtitle", targets: ["LiveSubtitle"]),
        .library(name: "Meetings", targets: ["Meetings"])
    ],
    targets: [
        .target(
            name: "ModelRuntime",
            path: "Modules/ModelRuntime/Sources/ModelRuntime"
        ),
        .target(
            name: "ModelLibrary",
            path: "Modules/ModelLibrary/Sources/ModelLibrary"
        ),
        .target(
            name: "LLMClient",
            path: "Modules/LLMClient/Sources/LLMClient"
        ),
        .target(
            name: "Settings",
            dependencies: ["LLMClient", "ModelRuntime"],
            path: "Modules/Settings/Sources/Settings"
        ),
        .target(
            name: "AudioCapture",
            path: "Modules/AudioCapture/Sources/AudioCapture"
        ),
        .target(
            name: "Meetings",
            dependencies: ["AudioCapture", "SceneChat", "Settings", "LLMClient", "ModelLibrary"],
            path: "Modules/Meetings/Sources/Meetings"
        ),
        .target(
            name: "LiveSubtitle",
            dependencies: ["AudioCapture", "Transcriber", "SceneChat", "Settings", "LLMClient"],
            path: "Modules/LiveSubtitle/Sources/LiveSubtitle"
        ),
        .target(
            name: "Transcriber",
            dependencies: ["AudioCapture"],
            path: "Modules/Transcriber/Sources/Transcriber"
        ),
        .target(
            name: "SceneChat",
            dependencies: ["LLMClient", "Settings", "ModelRuntime", "ModelLibrary"],
            path: "Modules/SceneChat/Sources/SceneChat"
        ),
        .target(
            name: "SelectionTranslate",
            dependencies: ["LLMClient", "Settings", "ModelRuntime", "ModelLibrary", "SceneChat"],
            path: "Modules/SelectionTranslate/Sources/SelectionTranslate"
        ),
        .testTarget(
            name: "ModelRuntimeTests",
            dependencies: ["ModelRuntime"],
            path: "Tests/ModelRuntimeTests",
            swiftSettings: testingSwiftSettings
        ),
        .testTarget(
            name: "ModelLibraryTests",
            dependencies: ["ModelLibrary"],
            path: "Tests/ModelLibraryTests",
            swiftSettings: testingSwiftSettings
        ),
        .testTarget(
            name: "LLMClientTests",
            dependencies: ["LLMClient", "ModelRuntime"],
            path: "Tests/LLMClientTests",
            swiftSettings: testingSwiftSettings
        ),
        .testTarget(
            name: "SettingsTests",
            dependencies: ["Settings"],
            path: "Tests/SettingsTests",
            swiftSettings: testingSwiftSettings
        ),
        .testTarget(
            name: "MeetingsTests",
            dependencies: ["Meetings", "AudioCapture", "Settings", "SceneChat", "ModelRuntime", "ModelLibrary", "LLMClient"],
            path: "Tests/MeetingsTests",
            swiftSettings: testingSwiftSettings
        ),
        .testTarget(
            name: "LiveSubtitleTests",
            dependencies: ["LiveSubtitle", "AudioCapture", "Transcriber", "Settings"],
            path: "Tests/LiveSubtitleTests",
            swiftSettings: testingSwiftSettings
        ),
        .testTarget(
            name: "TranscriberTests",
            dependencies: ["Transcriber", "AudioCapture"],
            path: "Tests/TranscriberTests",
            swiftSettings: testingSwiftSettings
        ),
        .testTarget(
            name: "AudioCaptureTests",
            dependencies: ["AudioCapture"],
            path: "Tests/AudioCaptureTests",
            swiftSettings: testingSwiftSettings
        ),
        .testTarget(
            name: "SelectionTranslateTests",
            dependencies: ["SelectionTranslate", "ModelRuntime", "ModelLibrary", "LLMClient", "Settings"],
            path: "Tests/SelectionTranslateTests",
            swiftSettings: testingSwiftSettings
        )
    ]
)