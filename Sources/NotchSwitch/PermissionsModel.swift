import AppKit
import Combine
import NotchKit

/// 权限状态模型：定时轮询 + 手动申请。
///
/// 为什么要轮询：TCC 授权发生在**系统设置**里，我们收不到任何通知，
/// 只能低频查一次（`CGPreflightScreenCaptureAccess` / `AXIsProcessTrusted` 都是廉价调用）。
@MainActor
final class PermissionsModel: ObservableObject {

    @Published private(set) var accessibilityGranted = false
    @Published private(set) var screenRecordingGranted = false
    /// 屏幕录制授权后需要重启才生效
    @Published private(set) var needsRelaunchForScreenRecording = false
    /// 辅助功能**刚**被授权（运行中的进程 AX 信任状态可能是陈旧的，建议重启）
    @Published private(set) var needsRelaunchForAccessibility = false

    /// 辅助功能从「未授权」变为「已授权」
    var onAccessibilityGranted: (() -> Void)?
    /// 辅助功能从「已授权」变为「未授权」（签名变更或用户手动关掉）
    var onAccessibilityRevoked: (() -> Void)?

    private var timer: Timer?
    private var screenRecordingWasDenied = false
    /// 首次读取只是「获取当前状态」，不能当成「刚刚授权」，否则每次启动都会误报需要重启
    private var hasLoadedInitialState = false

    var allGranted: Bool { accessibilityGranted && screenRecordingGranted }
    var needsRelaunch: Bool { needsRelaunchForScreenRecording || needsRelaunchForAccessibility }

    // MARK: - 运行位置
    //
    // TCC 把授权记录与「代码签名身份 + 路径」关联。放在临时目录、或重建后路径变化，
    // 都可能导致「系统设置里开关是开的，但 AXIsProcessTrusted() 仍返回 false」这种鬼状态。

    var bundlePath: String { Bundle.main.bundleURL.path }

    /// 是否运行在 .app 包里。用 `swift run` 直接跑二进制时没有 bundle，TCC 行为不可靠。
    var isAppBundle: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// 是否在「应用程序」文件夹下（推荐位置，系统设置里更容易找到，也不易失配）
    var isInApplicationsFolder: Bool {
        let path = bundlePath
        return path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/")
    }

    func start() {
        refresh()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        let accessibility = PermissionChecker.hasAccessibility
        let screenRecording = PermissionChecker.hasScreenRecording

        guard hasLoadedInitialState else {
            accessibilityGranted = accessibility
            screenRecordingGranted = screenRecording
            screenRecordingWasDenied = !screenRecording
            hasLoadedInitialState = true
            return
        }

        if accessibility != accessibilityGranted {
            let wasGranted = accessibilityGranted
            accessibilityGranted = accessibility
            if accessibility {
                needsRelaunchForAccessibility = true
                Log.app.notice("辅助功能权限已授予")
                onAccessibilityGranted?()
            } else if wasGranted {
                Log.app.notice("辅助功能权限丢失")
                onAccessibilityRevoked?()
            }
        }

        if screenRecording && !screenRecordingGranted && screenRecordingWasDenied {
            needsRelaunchForScreenRecording = true
        }
        if !screenRecording { screenRecordingWasDenied = true }
        if screenRecording != screenRecordingGranted { screenRecordingGranted = screenRecording }
    }

    // MARK: - 申请

    func requestAccessibility() {
        Log.app.notice("申请辅助功能权限（系统提示每次启动只弹一次；若不弹请用「打开系统设置」）")
        PermissionChecker.requestAccessibility()
        refresh()
    }

    func requestScreenRecording() {
        PermissionChecker.requestScreenRecording()
        refresh()
    }

    func openAccessibilitySettings() { PermissionChecker.openAccessibilitySettings() }
    func openScreenRecordingSettings() { PermissionChecker.openScreenRecordingSettings() }
}
