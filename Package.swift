// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NotchSwitch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NotchKit", targets: ["NotchKit"]),
        .executable(name: "NotchSwitch", targets: ["NotchSwitch"]),
    ],
    targets: [
        // 核心逻辑：刘海几何、面板、悬停、层级守卫（无 UI 依赖，可单测）
        .target(name: "NotchKit"),
        // 应用外壳：入口、菜单栏、窗口、SwiftUI 视图
        .executableTarget(name: "NotchSwitch", dependencies: ["NotchKit"]),
        .testTarget(name: "NotchKitTests", dependencies: ["NotchKit"]),
    ]
)
