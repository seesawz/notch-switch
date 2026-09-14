import AppKit
import ApplicationServices
import Combine

/// 窗口列表 + MRU 排序（PLAN.md §4.3）。
///
/// 数据来源：AX 枚举（含最小化窗口） + AXObserver 事件驱动重排 + NSWorkspace 启停通知。
/// **没有定时器轮询**：空闲时零 CPU。
@MainActor
public final class WindowListModel: ObservableObject {

    @Published public private(set) var windows: [WindowInfo] = []
    @Published public private(set) var diagnostics: String = ""
    @Published public private(set) var lastRefresh: Date?

    private var mru = MRUOrder()
    private let observerPool = AXObserverPool()
    private var throttledRefresh: DispatchWorkItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isStarted = false
    private var hasLoggedFirstRefresh = false

    /// 展开期间冻结显示顺序（PLAN.md R8）。
    ///
    /// 现在切换窗口后面板**不会**自动收起，用户可以连续切好几个。
    /// 而切换会改变 MRU 顺序，如果列表跟着重排，被点的那张卡会从鼠标底下跳走，
    /// 下一张想点的位置也全变了。所以展开期间只更新窗口**集合**，不动顺序；
    /// 收起后解除冻结并重排一次。
    public var isOrderFrozen = false

    /// AX 事件突发时的合并窗口（PLAN.md §4.3 的 200ms 节流）
    private let throttleInterval: TimeInterval = 0.2

    public init() {}

    public func start() {
        guard !isStarted else { return }
        isStarted = true

        observerPool.onFocusChanged = { [weak self] element in
            self?.handleFocusChange(element)
        }
        observerPool.onListChanged = { [weak self] in
            self?.scheduleRefresh()
        }

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
            workspaceObservers.append(observer)
        }

        refresh()
    }

    public func stop() {
        observerPool.stop()
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        throttledRefresh?.cancel()
        isStarted = false
    }

    // MARK: - 刷新

    public func refresh() {
        let enumerated = WindowEnumerator.enumerate()
        let ids = enumerated.map(\.id)

        mru.prune(keeping: Set(ids))
        // 新出现的窗口按 CGWindowList 的前后顺序并入队尾
        mru.seedUnknown(ids)

        if isOrderFrozen {
            windows = frozenOrder(preserving: windows.map(\.id), from: enumerated)
        } else {
            windows = mru.sorted(enumerated, id: \.id)
        }
        observerPool.sync(with: Set(enumerated.map(\.pid)))
        lastRefresh = Date()
        diagnostics = "\(enumerated.count) 个窗口 / \(Set(enumerated.map(\.pid)).count) 个应用 / 订阅 \(observerPool.observedProcessCount) 个应用"

        // 首次枚举用 notice 级，保证能被 log show 查到
        // （「一个窗口都没枚举到」是最常见的故障，必须有日志可查）
        if !hasLoggedFirstRefresh {
            hasLoggedFirstRefresh = true
            Log.panel.notice(
                """
                首次窗口枚举: \(self.diagnostics, privacy: .public) \
                windowID 映射=\(AXWindowID.isAvailable ? "私有API" : "位置匹配", privacy: .public)
                """
            )
        } else {
            Log.panel.debug("窗口列表刷新: \(self.diagnostics, privacy: .public)")
        }
    }

    /// 冻结期间的排序：原有窗口保持原位（只剔除已关闭的），新出现的追加到末尾。
    private func frozenOrder(preserving previousOrder: [CGWindowID], from enumerated: [WindowInfo]) -> [WindowInfo] {
        let byID = Dictionary(enumerated.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let previousSet = Set(previousOrder)

        let kept = previousOrder.compactMap { byID[$0] }
        let added = enumerated.filter { !previousSet.contains($0.id) }
        return kept + added
    }

    /// 事件驱动的节流刷新：突发 AX 事件合并成一次枚举，避免列表抖动
    public func scheduleRefresh() {
        throttledRefresh?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
        throttledRefresh = item
        DispatchQueue.main.asyncAfter(deadline: .now() + throttleInterval, execute: item)
    }

    private func handleFocusChange(_ element: AXUIElement) {
        // 通知里的 element 可能是应用也可能是窗口；统一解析到「被聚焦的窗口」
        var target = element
        if let focused = element.element(kAXFocusedWindowAttribute as String) {
            target = focused
        }

        guard let windowID = AXWindowID.windowID(of: target) else {
            scheduleRefresh()
            return
        }
        // 焦点变化是用户最直接的感知，立即重排，不走节流
        mru.touch(windowID)
        refresh()
    }

    // MARK: - 操作

    public func activate(_ window: WindowInfo) {
        WindowActivator.activate(window)
        mru.touch(window.id)
        scheduleRefresh()
    }

    /// 供调试面板显示
    public var debugDescription: String {
        var lines = [diagnostics]
        lines.append("MRU 记录 \(mru.order.count) 个窗口")
        lines.append("私有 API _AXUIElementGetWindow: \(AXWindowID.isAvailable ? "可用" : "不可用（回退按位置匹配）")")
        lines.append("")
        for (index, window) in windows.prefix(12).enumerated() {
            let mark = window.isMinimized ? " [最小化]" : ""
            lines.append(String(format: "%2d. %@ — %@%@", index + 1, window.appName, window.displayTitle, mark))
        }
        if windows.count > 12 {
            lines.append("... 其余 \(windows.count - 12) 个")
        }
        return lines.joined(separator: "\n")
    }
}
