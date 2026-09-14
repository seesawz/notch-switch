import AppKit
import ApplicationServices
import CoreGraphics

/// 两项必须的 TCC 权限检查与申请（PLAN.md §4.7）。
///
/// 权限与**代码签名身份**绑定：ad-hoc 签名会导致每次重装都要重新授权。
/// 所以本地开发前先跑一次 `scripts/setup-signing.sh` 建立固定签名身份。
@MainActor
public enum PermissionChecker {

    // MARK: - 辅助功能（窗口枚举 / MRU / 切换的硬前提）

    public static var hasAccessibility: Bool {
        AXIsProcessTrusted()
    }

    /// 申请辅助功能权限（会弹出系统提示）。重复调用不会重复弹窗。
    ///
    /// 这里用字符串字面量而不是 `kAXTrustedCheckOptionPrompt`：后者被导入为
    /// 可变的全局 `var`，在 Swift 6 严格并发下会报「not concurrency-safe」。
    @discardableResult
    public static func requestAccessibility() -> Bool {
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    // MARK: - 屏幕录制（窗口标题 / 缩略图的硬前提）

    public static var hasScreenRecording: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 申请屏幕录制权限。注意：授权后**通常需要重启 App** 才会生效。
    @discardableResult
    public static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - 跳转系统设置

    public static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    public static func openScreenRecordingSettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private static func open(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }
}
