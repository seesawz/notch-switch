import AppKit

/// 贴在刘海位置的透明面板。
///
/// 配置依据见 PLAN.md §4.1 / §4.1.1，每一项都有明确理由，改动前请先读那两节：
/// - `level = .screenSaver`：压过菜单栏(24)与所有普通 App 窗口(0)，实现「常驻最前台」
/// - `hidesOnDeactivate = false`：**NSPanel 默认是 `true`**，而 Agent App 会频繁失活，
///   不显式关掉就会「一激活别的 App 面板就消失」
/// - `collectionBehavior` **故意不加 `.fullScreenAuxiliary`**：这正是「其他 App 全屏时被遮挡」的实现手段
public final class NotchPanel: NSPanel {

    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // 常驻最前台所需的窗口属性
        hidesOnDeactivate = false
        worksWhenModal = true
        isFloatingPanel = true

        // 跨 Space 常驻；不加 .fullScreenAuxiliary（全屏例外）
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        // 视觉
        hasShadow = false
        backgroundColor = .clear
        isOpaque = false

        // 行为
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        animationBehavior = .none

        // 收起态由全局鼠标监听驱动，窗口本身完全不吃事件
        ignoresMouseEvents = true

        // ⚠️ level 必须放在**最后**设置。
        // `isFloatingPanel` 的 setter 会顺手把 window level 改成 `.floating`(3)，
        // 放在它前面设 `.screenSaver` 会被无声覆盖掉——面板就掉到菜单栏(24)下面去了，
        // 而且 UI 上表现为「东西不见了」，极难定位。
        // （这个 bug 是靠 Log.panel 打出 level 数值才发现的，日志不能省。）
        level = .screenSaver
    }

    /// 需要接收键盘（搜索）与滚轮（Shift 翻卡），因此允许成为 key window。
    /// `nonactivatingPanel` 保证它成为 key 时**不会**把本 App 激活到前台。
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}
