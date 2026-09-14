import AppKit
import NotchKit

/// 菜单栏常驻入口（Agent App 的唯一可见入口）。
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {

    struct Callbacks {
        var togglePanel: () -> Void
        var toggleHoverWithoutNotch: () -> Void
        var showDebugPanel: () -> Void
        var showPermissionGuide: () -> Void
        var relaunch: () -> Void
        var revealInFinder: () -> Void
        var quit: () -> Void
    }

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let permissions: PermissionsModel
    private let settings: AppSettings
    private var callbacks: Callbacks?

    private let accessibilityItem = NSMenuItem(title: "辅助功能权限", action: nil, keyEquivalent: "")
    private let screenRecordingItem = NSMenuItem(title: "屏幕录制权限", action: nil, keyEquivalent: "")
    private let locationItem = NSMenuItem(title: "运行位置", action: nil, keyEquivalent: "")
    private let hoverWithoutNotchItem = NSMenuItem(title: "无刘海屏幕顶部触发", action: #selector(toggleHoverWithoutNotch), keyEquivalent: "")
    private var appearanceTimer: Timer?

    init(permissions: PermissionsModel, settings: AppSettings) {
        self.permissions = permissions
        self.settings = settings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        buildMenu()
        statusItem.menu = menu
        updateAppearance()

        // 权限没拿齐时用警告图标，让用户一眼看出「这东西还没法用」
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateAppearance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        appearanceTimer = timer
    }

    func setCallbacks(_ callbacks: Callbacks) {
        self.callbacks = callbacks
    }

    private func buildMenu() {
        menu.autoenablesItems = false
        menu.delegate = self

        let header = NSMenuItem(title: "NotchSwitch 0.1.0", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for item in [accessibilityItem, screenRecordingItem, locationItem] {
            item.isEnabled = false
            menu.addItem(item)
        }

        let guide = NSMenuItem(title: "权限引导…", action: #selector(showPermissionGuide), keyEquivalent: "")
        guide.target = self
        menu.addItem(guide)

        let relaunchItem = NSMenuItem(title: "重启 NotchSwitch", action: #selector(relaunch), keyEquivalent: "")
        relaunchItem.target = self
        menu.addItem(relaunchItem)

        let reveal = NSMenuItem(title: "在访达中显示", action: #selector(revealInFinder), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: "展开 / 收起面板", action: #selector(togglePanel), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        // 无刘海机器上「是否保留顶部中央热区」的开关（ADR-036）。
        // 有刘海的屏幕用不到它——menuNeedsUpdate 里会按当前屏幕情况隐藏。
        hoverWithoutNotchItem.target = self
        menu.addItem(hoverWithoutNotchItem)

        let debug = NSMenuItem(title: "调试面板…", action: #selector(showDebugPanel), keyEquivalent: "d")
        debug.target = self
        menu.addItem(debug)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 NotchSwitch", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func updateAppearance() {
        guard let button = statusItem.button else { return }
        let granted = permissions.allGranted
        let symbol = granted ? "menubar.rectangle" : "exclamationmark.triangle.fill"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "NotchSwitch") {
            button.image = image
        } else {
            button.title = granted ? "◧" : "!"
        }
        button.toolTip = granted
            ? "NotchSwitch — 刘海窗口切换器"
            : "NotchSwitch 尚未完成授权，点这里处理"
    }

    /// 每次展开菜单时刷新状态，避免显示过期信息
    func menuNeedsUpdate(_ menu: NSMenu) {
        permissions.refresh()
        accessibilityItem.title = "辅助功能权限：\(permissions.accessibilityGranted ? "已授权" : "未授权")"
        screenRecordingItem.title = "屏幕录制权限：\(permissions.screenRecordingGranted ? "已授权" : "未授权")"
        locationItem.title = "运行位置：\(permissions.bundlePath)"

        // 只要有任何一块带刘海的屏幕，面板就贴刘海，这个开关就没有意义 → 隐藏。
        // 与 NotchPanelController.refreshScreen 的选屏规则一致：优先带刘海的屏。
        hoverWithoutNotchItem.isHidden = NSScreen.screens.contains { $0.notchFrame != nil }
        hoverWithoutNotchItem.state = settings.hoverWithoutNotch ? .on : .off
    }

    @objc private func togglePanel() { callbacks?.togglePanel() }
    @objc private func toggleHoverWithoutNotch() { callbacks?.toggleHoverWithoutNotch() }
    @objc private func showDebugPanel() { callbacks?.showDebugPanel() }
    @objc private func showPermissionGuide() { callbacks?.showPermissionGuide() }
    @objc private func relaunch() { callbacks?.relaunch() }
    @objc private func revealInFinder() { callbacks?.revealInFinder() }
    @objc private func quit() { callbacks?.quit() }
}
