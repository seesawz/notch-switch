import AppKit
import SwiftUI

/// 面板总控：负责几何、展开/收起、悬停联动、层级守卫联动、屏幕变化重排。
///
/// 职责边界：**只管窗口与状态**，内容由外部传入的 SwiftUI 视图决定。
@MainActor
public final class NotchPanelController {

    public enum State: Equatable {
        case collapsed
        case expanded
    }

    public private(set) var state: State = .collapsed
    public var onStateChange: ((State) -> Void)?

    /// 展开后内容区高度（**不含**刘海本身）
    public var contentHeight: CGFloat = 148
    /// 展开后面板宽度上限
    public var expandedWidthLimit: CGFloat = 772
    /// 收起后延迟多久折叠（滞回，避免边界抖动）
    public var collapseDelay: TimeInterval = 0.24
    /// 无刘海屏幕上是否保留「顶部中央」悬停热区（PLAN.md §4.8「或按设置不启用」）。
    /// 有刘海的屏幕不受影响；关闭只停用悬停触发，菜单栏的「展开 / 收起」始终可用。
    public var hoverWithoutNotch = true {
        didSet {
            guard hoverWithoutNotch != oldValue else { return }
            Log.panel.notice("无刘海顶部触发 → \(self.hoverWithoutNotch ? "开" : "关", privacy: .public)")
            // 关闭时面板还开着的话立刻收走——此时热区已消失，
            // 「鼠标移开」路径不会再触发，不收就永远挂在那了
            if !hoverWithoutNotch, state == .expanded {
                collapse(style: .collapseAction)
            }
        }
    }

    /// 面板几何的对外广播，供 SwiftUI 内容读取顶部留白与展开尺寸
    public let metrics: NotchMetrics

    /// 滚轮回调，参数是**内容位移量（点）**：正数 = 看更早的窗口，负数 = 看更新的窗口。
    /// 返回是否消费掉这次滚动（返回 `false` 时事件会继续传递，不会被面板吞掉）。
    public var onScroll: ((CGFloat) -> Bool)?

    /// 系统「减弱动态效果」是否开启。开启时展开/收起不做动画 ——
    /// Apple 对该选项的要求是 *"UI should avoid large animations"*。
    /// 由 `SystemDisplayOptions` 在运行时注入，不在这里读系统值。
    public var reduceMotion = false {
        didSet {
            guard reduceMotion != oldValue else { return }
            Log.panel.notice("减弱动态效果 → \(self.reduceMotion ? "开（展开/收起不做动画）" : "关", privacy: .public)")
        }
    }

    private let panel: NotchPanel
    private let container: NotchContentContainer
    private let hostingView: NSHostingView<AnyView>
    private let hover = HoverMonitor()
    private let layerGuard = LayerGuard()

    private var screen: NSScreen?
    private var notchFrame: CGRect = .zero
    private var expandedSize: CGSize = .zero
    private var topInset: CGFloat = 33

    private var isSuspended = false
    private var ownWindowPresented = false
    private var collapseWorkItem: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var scrollMonitor: Any?
    /// 监听面板 key 被系统转移（如点击卡片后目标 App 激活），展开中则夺回，维持液态玻璃
    private var keyObserver: NSObjectProtocol?

    public init(rootView: AnyView, metrics: NotchMetrics = NotchMetrics()) {
        self.metrics = metrics
        panel = NotchPanel(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40))
        container = NotchContentContainer()
        hostingView = NSHostingView(rootView: rootView)
    }

    /// 更新面板内容（例如权限状态变化后重建视图）
    public func setContent(_ view: AnyView) {
        hostingView.rootView = view
    }

    /// 当前是否因为「全屏 / 系统弹窗」而停摆
    public var isHoverSuspended: Bool { isSuspended }

    public var isExpanded: Bool { state == .expanded }

    // MARK: - 生命周期

    public func start() {
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.wantsLayer = true
        container.addSubview(hostingView)
        panel.contentView = container

        refreshScreen()
        applyFrame(for: .collapsed, transition: .immediate)
        // 显式设置一次层级，不依赖「守卫状态发生变化」这个前提
        applyLevel()
        panel.orderFrontRegardless()

        Log.panel.notice(
            """
            面板启动: 屏幕=\(self.screen?.localizedName ?? "nil", privacy: .public) \
            有刘海=\(self.screen?.hasNotch ?? false, privacy: .public) \
            刘海=\(self.notchFrame.debugString, privacy: .public) \
            顶部留白=\(Double(self.topInset), privacy: .public) \
            展开尺寸=\(Double(self.expandedSize.width), privacy: .public)x\(Double(self.expandedSize.height), privacy: .public) \
            level=\(self.panel.level.rawValue, privacy: .public)
            """
        )

        hover.hotZoneProvider = { [weak self] in self?.currentHotZone() }
        hover.onEnter = { [weak self] in self?.hoverEntered() }
        hover.onLeave = { [weak self] in self?.hoverExited() }
        hover.start()

        container.onScroll = { [weak self] contentOffset in
            self?.onScroll?(contentOffset) ?? false
        }
        installScrollMonitor()

        layerGuard.screenProvider = { [weak self] in self?.screen }
        layerGuard.onChange = { [weak self] blocker in self?.handleBlocker(blocker) }
        layerGuard.start()

        installKeyHoldObserver()

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleScreenParametersChanged() }
        }
    }

    public func stop() {
        hover.stop()
        layerGuard.stop()
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        screenObserver = nil
        if let observer = keyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        keyObserver = nil
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
        scrollMonitor = nil
        panel.orderOut(nil)
    }
    /// 滚动监听（PLAN.md §6.5 / ADR-010）。
    ///
    /// 两条路径同时装，用**事件时间戳**去重，保证同一个事件只被处理一次：
    ///  1. `NotchContentContainer.scrollWheel(with:)` —— 事件派发到窗口后沿响应者链上浮
    ///  2. 本地 monitor —— 事件派发**之前**就能拿到，更可靠
    /// 之所以要 2，是因为 `NSHostingView` 有可能自己吞掉滚动事件，导致 1 收不到；
    /// 之所以还要保留 1，是因为 local monitor 依赖本 App 在事件投递链上，
    /// 多一层兜底不至于让 Shift 滚轮整个失效。
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }

            // 先把需要的原始值取出来：NSEvent 不是 Sendable，不能带进 MainActor 闭包
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY
            let isPrecise = event.hasPreciseScrollingDeltas
            let timestamp = event.timestamp

            let consumed = MainActor.assumeIsolated {
                self.panel.frame.contains(NSEvent.mouseLocation)
                    && self.container.handleScroll(
                        deltaX: deltaX,
                        deltaY: deltaY,
                        hasPreciseDeltas: isPrecise,
                        timestamp: timestamp
                    )
            }
            return consumed ? nil : event   // 已消费则不再向下传递
        }
    }

    // MARK: - 手动控制（菜单栏用）

    /// 菜单栏的「展开 / 收起」。收起用 `.collapseAction`：
    /// 这是用户明确下达的指令，要迅速让开，不该用鼠标移开那种较慢的节奏。
    public func toggle() {
        state == .expanded ? collapse(style: .collapseAction) : expand()
    }

    public func expand() {
        guard !isSuspended, state != .expanded else {
            // 「悬停没反应」时，这行日志直接给出原因
            Log.panel.debug(
                "expand 被拒绝: suspended=\(self.isSuspended, privacy: .public) state=\(String(describing: self.state), privacy: .public)"
            )
            return
        }
        cancelPendingCollapse()
        state = .expanded
        panel.ignoresMouseEvents = false
        holdKeyForLiquidGlass()
        let transition = effectiveTransition(.expand)
        applyFrame(for: .expanded, transition: transition)
        metrics.setExpanded(true, transition: transition)
        onStateChange?(state)
        Log.panel.notice("展开 → \(self.targetFrame(for: .expanded).debugString, privacy: .public)")

        // 调试：等动画与缩略图稳定后把面板区域截下来（见 PanelCapture 说明）
        if PanelCapture.isEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.state == .expanded else { return }
                    PanelCapture.capturePanelRegion(panelFrame: self.targetFrame(for: .expanded), expanded: true)
                }
            }
        }
    }

    /// - Parameter style: 收起档位。点击卡片后用 `.collapseAction`——
    ///   用户已经做完决定了，面板要更快更干脆地让开，而不是慢慢缩回去。
    public func collapse(style: PanelTransition = .collapseHover) {
        guard state != .collapsed else { return }
        cancelPendingCollapse()
        state = .collapsed
        panel.ignoresMouseEvents = true
        releaseKey()
        let transition = effectiveTransition(style)
        applyFrame(for: .collapsed, transition: transition)
        metrics.setExpanded(false, transition: transition)
        onStateChange?(state)
        Log.panel.notice("收起 → \(self.targetFrame(for: .collapsed).debugString, privacy: .public)")

        // 调试对照：收起态截同一块区域，用来区分「是面板的问题」还是「系统本来的样子」
        if PanelCapture.isEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.state == .collapsed else { return }
                    PanelCapture.capturePanelRegion(panelFrame: self.targetFrame(for: .expanded), expanded: false)
                }
            }
        }
    }

    /// 本 App 自己弹窗（设置 / 调试面板）时调用：临时降级，避免自己的窗口被自己挡住。
    public func setOwnWindowPresented(_ presented: Bool) {
        ownWindowPresented = presented
        applyLevel()
    }

    // MARK: - key 与 Liquid Glass
    //
    // 实测结论（scripts/glass_probe.swift，截图 + 像素统计验证）：
    // `NSGlassEffectView` 只在「自己的窗口是 key window」时才渲染液态玻璃；
    // 非 key 时渲染成一块平坦的暗色贴片，背后内容完全透不过来。
    // 覆写 `isKeyWindow` 对外说谎无效（玻璃读的是 WindowServer 的真实 key 状态）。
    //
    // 所以：面板展开期间必须真正持有 key，玻璃才能常亮。这样做是安全的：
    // 面板是 `nonactivatingPanel`，成为 key **不会激活本 App**，前台 App 保持 active，
    // 键盘输入仍路由给前台 App；key 身份只影响本 App 内部（正好只影响玻璃渲染）。

    /// 展开时持有 key，点亮液态玻璃。
    /// 自己弹窗（设置/调试）打开时不抢，避免夺走自家窗口的 key。
    private func holdKeyForLiquidGlass() {
        guard !ownWindowPresented else { return }
        panel.makeKey()
        Log.panel.debug("展开 → makeKey（点亮液态玻璃）key=\(self.panel.isKeyWindow, privacy: .public)")
    }

    /// 收起时交还 key。玻璃随 key 失效变平无所谓——面板已缩回刘海，本来就看不见。
    private func releaseKey() {
        guard panel.isKeyWindow else { return }
        panel.resignKey()
        Log.panel.debug("收起 → resignKey（交还键盘焦点）")
    }

    /// 面板展开期间 key 被系统转移（典型：点击卡片后目标 App 激活）→ 夺回，
    /// 否则从点击那一刻起玻璃又变回平坦外观（正是「液态玻璃只有点击时闪现」的另一半成因）。
    /// 刻意收起（state == .collapsed）时不夺回，避免和 releaseKey 打架。
    private func installKeyHoldObserver() {
        guard keyObserver == nil else { return }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .expanded, !self.ownWindowPresented else { return }
                Log.panel.debug("key 被系统转移但面板仍展开 → 重新 makeKey 维持液态玻璃")
                self.panel.makeKey()
            }
        }
    }

    // MARK: - 悬停联动

    private func hoverEntered() {
        guard !isSuspended, !ownWindowPresented else { return }
        cancelPendingCollapse()
        expand()
    }

    private func hoverExited() {
        scheduleCollapse(after: collapseDelay)
    }

    private func scheduleCollapse(after delay: TimeInterval) {
        cancelPendingCollapse()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.collapse() }
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelPendingCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    // MARK: - 层级守卫联动

    private func handleBlocker(_ blocker: LayerGuard.Blocker) {
        switch blocker {
        case .none:
            isSuspended = false
            applyLevel()
            panel.orderFrontRegardless()
            Log.panel.notice("恢复常驻最前台（level=\(self.panel.level.rawValue, privacy: .public)）")
        case .fullScreenApp:
            // 需求规定的唯一例外：全屏 App 就该挡住我们
            isSuspended = true
            collapse()
        case .systemModal:
            // 让出层级，否则会盖住授权按钮
            isSuspended = true
            collapse()
            applyLevel()
            Log.panel.notice("面板 level 降级为 \(self.panel.level.rawValue, privacy: .public) 以免遮挡系统弹窗")
        }
    }

    private func applyLevel() {
        if ownWindowPresented || layerGuard.blocker == .systemModal {
            panel.level = .floating
        } else {
            panel.level = .screenSaver
        }
        // 层级是「常驻最前台」的命门，任何一次变化都留痕（level 1000 = .screenSaver）
        Log.layer.debug("panel level → \(self.panel.level.rawValue, privacy: .public)")
    }

    // MARK: - 几何

    private func handleScreenParametersChanged() {
        Log.panel.notice("屏幕参数变化（插拔/分辨率/缩放）→ 重算几何")
        refreshScreen()
        collapse()
        applyFrame(for: .collapsed, transition: .immediate)
        Log.panel.notice("新几何: 刘海=\(self.notchFrame.debugString, privacy: .public) 顶部留白=\(Double(self.topInset), privacy: .public)")
    }

    private func refreshScreen() {
        let screens = NSScreen.screens

        if let notched = screens.first(where: { $0.notchFrame != nil }), let frame = notched.notchFrame {
            screen = notched
            notchFrame = frame
        } else if let fallback = NSScreen.main ?? screens.first {
            // 无刘海机器 / 全外接屏：退化为「菜单栏中央一段」（PLAN.md §4.8）
            screen = fallback
            let width = min(320, fallback.frame.width * 0.25)
            let height = max(fallback.menubarHeight, 24)
            notchFrame = CGRect(
                x: fallback.frame.midX - width / 2,
                y: fallback.frame.maxY - height,
                width: width,
                height: height
            )
        } else {
            screen = nil
            notchFrame = .zero
        }

        // 内容顶部留白取「刘海高度」与「菜单栏高度」的较大值：
        // 有刘海的屏幕上二者相差 1pt 左右，取大值可确保内容不压到菜单栏。
        topInset = max(notchFrame.height, screen?.menubarHeight ?? 0)

        let available = (screen?.frame.width ?? 1440) - 40
        expandedSize = CGSize(
            width: min(expandedWidthLimit, available),
            height: topInset + contentHeight
        )
        container.contentSize = expandedSize

        metrics.update(
            topInset: topInset,
            expandedSize: expandedSize,
            hasNotch: screen?.hasNotch ?? false
        )
    }

    /// 收起 / 展开的目标 frame：**上沿与水平中心恒定**，只改变宽高 → 视觉上从刘海长出来。
    private func targetFrame(for state: State) -> CGRect {
        let size = state == .expanded
            ? expandedSize
            : CGSize(width: notchFrame.width, height: notchFrame.height)
        return CGRect(
            x: notchFrame.midX - size.width / 2,
            y: notchFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// 系统「减弱动态效果」开启时，任何过渡都降级为「立即」。
    /// frame 动画与 SwiftUI 内容动画都必须用这个结果，否则两边会对不上。
    private func effectiveTransition(_ transition: PanelTransition) -> PanelTransition {
        reduceMotion ? .immediate : transition
    }

    private func applyFrame(for state: State, transition: PanelTransition) {
        container.contentSize = expandedSize
        let target = targetFrame(for: state)

        guard transition != .immediate else {
            panel.setFrame(target, display: true)
            container.needsLayout = true
            return
        }

        let points = transition.controlPoints
        NSAnimationContext.runAnimationGroup { context in
            context.duration = transition.duration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: Float(points.x1), Float(points.y1),
                Float(points.x2), Float(points.y2)
            )
            panel.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.container.needsLayout = true }
        }
    }

    /// 热区：收起态略微外扩（否则贴着刘海很难命中），展开态跟随面板整体。
    /// 无刘海屏幕且设置关闭时返回 `nil` —— 悬停完全不触发（`HoverMonitor` 对 nil 直接跳过）。
    private func currentHotZone() -> CGRect? {
        // 每次现算而不是缓存：插拔显示器后 hasNotch 会变，热区必须立刻跟上
        guard hoverWithoutNotch || screen?.hasNotch == true else { return nil }
        switch state {
        case .collapsed:
            return notchFrame.insetBy(dx: -48, dy: -10)
        case .expanded:
            return targetFrame(for: .expanded).insetBy(dx: -10, dy: -10)
        }
    }

    // MARK: - 调试用

    public var debugDescription: String {
        let screenName = screen?.localizedName ?? "nil"
        return """
        屏幕: \(screenName)
        刘海 frame: \(notchFrame)
        顶部留白: \(topInset)
        展开尺寸: \(expandedSize)
        当前状态: \(state)
        窗口 frame: \(panel.frame)
        层级: \(panel.level.rawValue)
        挂起: \(isSuspended)  守卫: \(layerGuard.blocker)
        热区: \(currentHotZone()?.debugString ?? "nil（无刘海且已按设置禁用）")
        无刘海顶部触发: \(hoverWithoutNotch ? "开" : "关")
        鼠标位置: \(NSEvent.mouseLocation.debugString)
        自身窗口: \(ownWindowPresented)
        悬停状态: \(hover.debugState)
        """
    }
}
