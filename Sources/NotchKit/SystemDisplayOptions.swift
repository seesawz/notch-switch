import AppKit
import Combine

/// 用户在「系统设置」里设定过的显示 / 辅助功能选项。
///
/// **为什么必须读它们，而不是自己定死数值**：这些是用户明确表达过的偏好，
/// macOS 通过公开 API 提供（`NSWorkspace (NSWorkspaceAccessibilityDisplay)`，macOS 10.10+），
/// 而且 Apple 在头文件注释里直接写明了期望行为。逐条对照本项目的玻璃面板：
///
/// | 系统选项 | Apple 的原文要求 | 对本项目意味着 |
/// |---|---|---|
/// | 减弱透明度 | *"UI (mainly **window**) backgrounds should **not be semi-transparent**; they should be **opaque**"* | 🚨 面板背景**必须变成不透明**，不能再用玻璃 |
/// | 增强对比度 | *"utilizing a less subtle color palette or **bolder lines**"* | 描边加粗、提高不透明度 |
/// | 减弱动态效果 | *"UI should avoid **large animations**"* | 展开/收起不做动画 |
/// | 不依赖颜色区分 | *"should not convey information using **color alone**"* | 状态要同时用图形表达 |
///
/// 全部可运行时变更，监听 `NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification`
/// 后无需重启即可跟随。
@MainActor
public final class SystemDisplayOptions: ObservableObject {

    /// 减弱透明度 —— 为 true 时面板背景必须不透明（见类型注释里的原文要求）
    @Published public private(set) var reduceTransparency = false
    /// 增强对比度 —— 为 true 时用更粗的描边与更高的不透明度
    @Published public private(set) var increaseContrast = false
    /// 减弱动态效果 —— 为 true 时展开/收起不做动画
    @Published public private(set) var reduceMotion = false
    /// 不依赖颜色区分 —— 为 true 时状态不能只靠颜色表达
    @Published public private(set) var differentiateWithoutColor = false

    private var observers: [NSObjectProtocol] = []

    public init() {}

    public func start() {
        read()
        let center = NSWorkspace.shared.notificationCenter
        // 通知名直接用字符串常量值：这是 APPKIT_EXTERN 的文件级常量，
        // 写成字面量与它的真实值完全一致，比猜 Swift 导入名更稳妥。
        let name = Notification.Name("NSWorkspaceAccessibilityDisplayOptionsDidChangeNotification")
        observers.append(
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.read()
                    Log.app.notice(
                        "系统显示选项变化: 减弱透明度=\(self?.reduceTransparency ?? false, privacy: .public) 增强对比度=\(self?.increaseContrast ?? false, privacy: .public) 减弱动效=\(self?.reduceMotion ?? false, privacy: .public)"
                    )
                }
            }
        )
    }

    public func stop() {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    /// 当前生效的玻璃材质。系统值变了要重新算，所以是计算属性而不是缓存。
    public var resolvedGlassMaterial: GlassMaterial {
        GlassMaterialPolicy.resolve(
            reduceTransparency: reduceTransparency,
            supportsLiquidGlass: GlassMaterialPolicy.isLiquidGlassAvailable,
            blurOverride: GlassMaterialPolicy.hasBlurOverride
        )
    }

    private func read() {
        let workspace = NSWorkspace.shared
        let next = (
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor
        )
        if reduceTransparency != next.reduceTransparency { reduceTransparency = next.reduceTransparency }
        if increaseContrast != next.increaseContrast { increaseContrast = next.increaseContrast }
        if reduceMotion != next.reduceMotion { reduceMotion = next.reduceMotion }
        if differentiateWithoutColor != next.differentiateWithoutColor {
            differentiateWithoutColor = next.differentiateWithoutColor
        }
    }

    public var debugDescription: String {
        """
        减弱透明度: \(reduceTransparency ? "开" : "关")
        增强对比度: \(increaseContrast ? "开" : "关")
        减弱动态效果: \(reduceMotion ? "开" : "关")
        不依赖颜色: \(differentiateWithoutColor ? "开" : "关")
        玻璃材质: \(resolvedGlassMaterial)
        """
    }
}
