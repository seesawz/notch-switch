import ApplicationServices
import Darwin
import Foundation

/// AXUIElement → CGWindowID 的映射（PLAN.md §4.2 / ADR-005）。
///
/// 为什么需要它：AX 接口拿不到窗口的 CGWindowID，而 ScreenCaptureKit 只认 CGWindowID。
/// 没有这层映射，就无法把「窗口」和「它的截图」对应起来。
///
/// 用的是私有符号 `_AXUIElementGetWindow`（AltTab / DockDoor / yabai 都在用，长期稳定），
/// 但 PrivateAPI 隔离采用 **dlsym 动态查找**：
/// 一旦系统更新去掉了这个符号，这里静默降级为 nil，由上层回退到「按 pid + 位置」匹配，
/// 而不是直接崩溃。
public enum AXWindowID {

    private typealias GetWindowFunction = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    /// 解析出的私有函数指针。用 `let` + 立即执行闭包，避免可变全局状态（Swift 6 并发检查）。
    private static let function: GetWindowFunction? = {
        // RTLD_DEFAULT：在已加载的所有镜像里查找符号
        guard let handle = UnsafeMutableRawPointer(bitPattern: -2),
              let symbol = dlsym(handle, "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindowFunction.self)
    }()

    /// 私有符号是否可用（用于日志与调试面板）
    public static var isAvailable: Bool { function != nil }

    /// 取窗口的 CGWindowID
    public static func windowID(of element: AXUIElement) -> CGWindowID? {
        guard let function else { return nil }
        var windowID: CGWindowID = 0
        guard function(element, &windowID) == .success, windowID != 0 else { return nil }
        return windowID
    }
}
