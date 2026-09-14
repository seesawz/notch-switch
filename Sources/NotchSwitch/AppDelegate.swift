import AppKit
import NotchKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    /// 切换窗口后，卡片确认高亮保持多久
    private let activationHighlightDuration: TimeInterval = 0.5

    private let permissions = PermissionsModel()
    private let metrics = NotchMetrics()
    private let windowList = WindowListModel()
    private let thumbnails = ThumbnailStore()
    private let selection = PanelSelection()
    private var panelController: NotchPanelController?
    private var statusItemController: StatusItemController?

    private var guideWindow: NSWindow?
    private var debugWindow: NSWindow?
    private var auxiliaryWindows: [NSWindow] = []

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.notice("NotchSwitch 启动 · bundle=\(Bundle.main.bundleURL.path, privacy: .public)")
        // 滚动方向以用户的系统设置为依据（ADR-024），启动时留痕可审计
        Log.app.notice("滚动方向设置: 自然滚动=\(ScrollDelta.naturalScrollingEnabled, privacy: .public)（预览带语义：下滚/左滑=前进）")
        permissions.start()

        permissions.onAccessibilityGranted = { [weak self] in
            // 不抢焦点，只把引导窗口提到本 App 最前，让用户看到状态已更新
            self?.guideWindow?.orderFront(nil)
        }

        // 窗口枚举是 AX 事件驱动 + 首次全量枚举，启动时跑一次
        windowList.start()
        // 启动时面板是收起的 —— 正是抓缩略图的时机
        refreshThumbnailsWhileHidden()

        let controller = NotchPanelController(
            rootView: AnyView(
                NotchRootView(
                    permissions: permissions,
                    metrics: metrics,
                    windowList: windowList,
                    thumbnails: thumbnails,
                    selection: selection,
                    onActivate: { [weak self] window in self?.activate(window) }
                )
            ),
            metrics: metrics
        )
        panelController = controller

        // 滚轮翻卡（PLAN.md §6.5）：传入连续位移量，由 PanelSelection 做帧同步跟随
        controller.onScroll = { [weak self] contentOffset in
            guard let self else { return false }
            let total = self.windowList.windows.count
            self.selection.update(totalCount: total)
            // 卡片不超过一屏时没有可滚动内容，不消费事件，避免白白吞掉用户的滚动
            guard self.selection.maxOffset > 0 else { return false }
            self.selection.scroll(by: contentOffset, totalCount: total)
            return true
        }

        // 展开时刷新列表与缩略图；收起时复位可见区
        controller.onStateChange = { [weak self] state in
            guard let self else { return }
            switch state {
            case .expanded:
                // 展开期间冻结排序：切换窗口会改变 MRU，列表跟着重排的话
                // 被点的卡片会从鼠标底下跳走，下一张想点的位置也全变了
                self.windowList.isOrderFrozen = true
                self.windowList.refresh()
                // 这里**故意不抓缩略图**：面板在 level 1000，此刻正盖在源窗口上方，
                // 抓出来的图上半部分会是我们自己的面板（表现为「卡片上半发白」）。
                // 缩略图统一在面板不可见时补（见 .collapsed 分支与启动时）。
            case .collapsed:
                self.selection.reset()
                // 收起后解除冻结并重排一次，下次展开就是最新的最近使用顺序
                self.windowList.isOrderFrozen = false
                self.windowList.scheduleRefresh()
                self.refreshThumbnailsWhileHidden()
            }
        }

        controller.start()

        let statusItem = StatusItemController(permissions: permissions)
        statusItem.setCallbacks(
            .init(
                togglePanel: { [weak self] in self?.panelController?.toggle() },
                showDebugPanel: { [weak self] in self?.showDebugPanel() },
                showPermissionGuide: { [weak self] in self?.showPermissionGuide() },
                relaunch: { [weak self] in self?.relaunch() },
                revealInFinder: {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                },
                quit: { NSApp.terminate(nil) }
            )
        )
        statusItemController = statusItem

        showPermissionGuideIfMissing()
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.stop()
        permissions.stop()
        windowList.stop()
    }

    /// 抓缩略图。**必须等面板不可见时再做**。
    ///
    /// 原因：面板窗口在 `level = .screenSaver`，抓图时它正盖在源窗口上方，
    /// ScreenCaptureKit 抓到的画面里就带着我们自己的面板 ——
    /// 表现成「每张卡片的上半部分都是一条整齐的浅色带」。
    /// 这个 bug 靠肉眼几乎不可能定位到缩略图本身，是导出原始缩略图 + 像素级对照才确认的。
    private func refreshThumbnailsWhileHidden() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.panelController?.isExpanded != true else { return }
            self.thumbnails.refresh(for: self.windowList.windows)
        }
    }

    /// 点击卡片：切窗口 + 收起面板
    private func activate(_ window: WindowInfo) {
        windowList.activate(window)

        // 面板**不自动收起**：可以连着切好几个窗口，只有鼠标移开才收起。
        // 所以这里刻意不做任何 collapse 调用，也不去干扰「鼠标移开」那条路径
        // （如果鼠标正在离开，就应该让它正常收走）。

        // 确认高亮只亮一下，避免一直挂着
        selection.markActivating(window.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + activationHighlightDuration) { [weak self] in
            self?.selection.clearActivating(window.id)
        }
    }

    // MARK: - 权限引导
    //
    // 只要还有权限没拿到，**每次启动都要弹**。
    // 早期版本用了一个「只提示一次」的持久化标记，用户关掉窗口后就再也没有入口了——
    // 而辅助功能的系统提示每次启动只弹一次，等于把用户堵死。这个标记已删除。

    private func showPermissionGuideIfMissing() {
        guard !permissions.allGranted else { return }
        Log.app.notice("权限未齐（辅助功能=\(self.permissions.accessibilityGranted, privacy: .public) 屏幕录制=\(self.permissions.screenRecordingGranted, privacy: .public)）→ 打开引导窗口")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.showPermissionGuide()
        }
    }

    private func showPermissionGuide() {
        if let window = guideWindow {
            present(window)
            return
        }
        let window = makeWindow(
            title: "NotchSwitch 权限",
            view: AnyView(
                PermissionGuideView(
                    permissions: permissions,
                    onRelaunch: { [weak self] in self?.relaunch() }
                )
            ),
            styleMask: [.titled, .closable]
        )
        guideWindow = window
        present(window)
    }

    // MARK: - 重启
    //
    // 授权后重启是必要的：运行中的进程 AX 信任状态可能是陈旧的，
    // 会出现「已授权但 AX 调用仍失败」。宁可让用户点一下重启。

    private func relaunch() {
        let bundleURL = Bundle.main.bundleURL
        guard bundleURL.pathExtension == "app" else {
            Log.app.error("当前不是 .app 包运行，无法自动重启，请手动重启")
            return
        }
        Log.app.notice("重启 NotchSwitch")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor in
                if let error {
                    Log.app.error("重启失败: \(error.localizedDescription, privacy: .public)")
                    return
                }
                self?.panelController?.stop()
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - 辅助窗口

    private func showDebugPanel() {
        if let window = debugWindow {
            present(window)
            return
        }
        let window = makeWindow(
            title: "NotchSwitch 调试",
            view: AnyView(DebugPanelView(textProvider: { [weak self] in self?.debugText() ?? "" })),
            styleMask: [.titled, .closable, .resizable, .miniaturizable]
        )
        debugWindow = window
        present(window)
    }

    private func makeWindow(title: String, view: AnyView, styleMask: NSWindow.StyleMask) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 620, height: 520),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow) {
        if !auxiliaryWindows.contains(where: { $0 === window }) {
            auxiliaryWindows.append(window)
        }
        // 我们自己的窗口不能被 level=1000 的面板挡住，因此让面板临时降级
        panelController?.setOwnWindowPresented(true)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Log.app.notice("打开辅助窗口: \(window.title, privacy: .public)")
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        auxiliaryWindows.removeAll { $0 === window }
        panelController?.setOwnWindowPresented(!auxiliaryWindows.isEmpty)
    }

    // MARK: - 调试文本

    private func debugText() -> String {
        var lines: [String] = []
        lines.append("NotchSwitch 调试信息")
        lines.append("时间: \(Date())")
        lines.append("bundle: \(Bundle.main.bundleURL.path)")
        lines.append("")
        lines.append("== 屏幕 ==")
        for (index, screen) in NSScreen.screens.enumerated() {
            let isMain = screen == NSScreen.main ? "  ← main" : ""
            lines.append("[\(index)] \(screen.localizedName)\(isMain)")
            lines.append("    frame          = \(screen.frame.debugString)")
            lines.append("    visibleFrame   = \(screen.visibleFrame.debugString)")
            lines.append("    safeAreaInsets = top \(screen.safeAreaInsets.top), bottom \(screen.safeAreaInsets.bottom)")
            lines.append("    auxTopLeft     = \(screen.auxiliaryTopLeftArea?.debugString ?? "nil")")
            lines.append("    auxTopRight    = \(screen.auxiliaryTopRightArea?.debugString ?? "nil")")
            lines.append("    notchFrame     = \(screen.notchFrame?.debugString ?? "nil（无刘海）")")
            lines.append("    menubarHeight  = \(screen.menubarHeight)")
            lines.append("    scale          = \(screen.backingScaleFactor)")
            lines.append("")
        }
        lines.append("== 面板 ==")
        lines.append(panelController?.debugDescription ?? "未启动")
        lines.append("")
        lines.append("== 窗口列表 ==")
        lines.append(windowList.debugDescription)
        lines.append("")
        lines.append("== 缩略图 ==")
        lines.append("已缓存 \(thumbnails.images.count) 张")
        lines.append("抓取中: \(thumbnails.isCapturing)")
        if let error = thumbnails.lastError { lines.append("错误: \(error)") }
        lines.append("")
        lines.append("== 权限 ==")
        lines.append("辅助功能: \(permissions.accessibilityGranted ? "已授权" : "未授权")")
        lines.append("屏幕录制: \(permissions.screenRecordingGranted ? "已授权" : "未授权")")
        lines.append("运行位置: \(permissions.bundlePath)")
        lines.append("在应用程序文件夹: \(permissions.isInApplicationsFolder)")
        lines.append("")
        lines.append("== 日志 ==")
        lines.append("终端查看:")
        lines.append("  /usr/bin/log stream --debug --predicate 'subsystem == \"com.notchswitch.app\"'")
        return lines.joined(separator: "\n")
    }
}
