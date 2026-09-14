import AppKit
import ApplicationServices

/// 把窗口切到前台（PLAN.md §4.6）。
///
/// 三级策略，逐级降级：
///  1. 取消最小化（否则后面所有操作都作用在一个收起来的窗口上）
///  2. 激活所属 App
///  3. AX 提升窗口 + 设为 focused window
@MainActor
public enum WindowActivator {

    @discardableResult
    public static func activate(_ window: WindowInfo) -> Bool {
        // 1. 最小化 → 先取消
        if window.isMinimized {
            window.axElement.setValue(kCFBooleanFalse, for: kAXMinimizedAttribute as String)
        }

        // 2. 激活 App。注意：这一步会切换 Space（如果窗口在别的 Space 上）
        var activated = false
        if let app = NSRunningApplication(processIdentifier: window.pid) {
            activated = app.activate(from: .current, options: [])
        }

        // 3. 提升并聚焦该窗口。
        //    只激活 App 是不够的——同应用多窗口时，激活 App 不保证聚焦到指定的那个窗口。
        let axApp = AXUIElementCreateApplication(window.pid)
        axApp.setValue(window.axElement, for: kAXFocusedWindowAttribute as String)
        window.axElement.setValue(kCFBooleanTrue, for: kAXMainAttribute as String)
        window.axElement.perform(kAXRaiseAction as String)

        Log.panel.notice(
            """
            切换窗口: \(window.displayTitle, privacy: .public) \
            pid=\(window.pid, privacy: .public) \
            activated=\(activated, privacy: .public) \
            最小化=\(window.isMinimized, privacy: .public)
            """
        )
        return activated
    }
}
