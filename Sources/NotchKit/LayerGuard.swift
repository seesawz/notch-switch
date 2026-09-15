import AppKit
import ApplicationServices

/// 层级守卫：维护「常驻最前台」这个承诺的**两个例外**（PLAN.md §4.1.1）。
///
/// - `fullScreenApp`：其他 App 进入全屏 → 我们主动收起（这就是需求里要的那个例外）
/// - `systemModal`：系统模态弹窗（授权框等）出现 → 我们临时降级 level 让出去。
///   这一条不做的话，level=1000 的面板会盖住授权按钮，用户点不到，流程直接卡死。
///
/// ── 全屏状态用「闩锁」而非逐拍轮询（实测得出的关键结论）──
///
/// 全屏的**检测只在 Space 切换的瞬间可靠**，稳态下两个检测器都会漏判
/// （2026-09-15 实测，macOS 26/27）：
/// - CGWindowList：稳态全屏窗口是 `(0, 菜单栏高, 屏宽, 屏高-菜单栏高)`，
///   不覆盖菜单栏条，与「最大化窗口」同形，且另有 layer 500 跨屏容器等形态；
/// - AX：稳态下窗口 frame 报的是**还原前**的旧尺寸，subrole 也不是
///   `AXFullScreenWindow` 而是普通值（实测飞书报 `AXUnknown`）。
///
/// 而 `activeSpaceDidChangeNotification` 进出全屏**必然触发**，且触发瞬间
/// 两个检测器都能正确判定（动画中的窗口暂具全屏形态）。因此：
/// 检测命中 → 置闩；解除**只**发生在「space 变化且检测未命中」时，
/// 看门狗的逐拍 miss 一律不解闩——否则全屏稳态里守卫会反复「置位 → 解除」，
/// 解除空档里面板照样弹出（正是本 bug 的原始表现）。
@MainActor
public final class LayerGuard {

    public enum Blocker: Equatable {
        case none
        /// 其他 App 处于全屏
        case fullScreenApp
        /// 系统模态弹窗出现，需要让出层级
        case systemModal
    }

    public private(set) var blocker: Blocker = .none
    public var onChange: ((Blocker) -> Void)?
    /// 由外部提供当前关注的屏幕（避免此处强引用 NSScreen）
    public var screenProvider: (() -> NSScreen?)?

    /// 会遮挡授权流程的系统进程。命中任一即认为需要让出层级。
    static let systemModalOwners: Set<String> = [
        "UserNotificationCenter",
        "CoreServicesUIAgent",
        "SecurityAgent",
        "tccd",
        "System Settings",
    ]

    private var spaceObserver: NSObjectProtocol?
    private var watchdog: Timer?
    private var isRunning = false

    // MARK: 全屏闩锁状态

    /// 当前（关注的屏幕上）是否处于全屏 Space。只在 space 变化的评估里解除。
    private var fullScreenLatch = false
    /// 闩置位的时间。用于识别「进入动画的第二发 space 通知」：它在置位后
    /// ~1.2s 内到达且检测不到全屏（稳态已开始漏判），不能据此解闩。
    private var fullScreenLatchSetAt = Date.distantPast
    /// 解除前的复核任务（退出动画可能让检测短暂为真，延迟一拍再确认）
    private var clearVerifyWork: DispatchWorkItem?
    /// 闩置位后多少秒内，space 变化的 miss 视为「进入动画余波」而不解闩。
    /// 实测第二发通知距置位 ~1.2s，取 2.0s 留裕量。
    private static let echoGraceInterval: TimeInterval = 2.0
    /// 复核延迟：space 变化后等动画收尾再确认一次是否真的退出全屏。
    private static let clearVerifyDelay: TimeInterval = 0.6

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate(isSpaceChange: true) }
        }

        // 低频看门狗：负责**补置闩**（space 通知偶发错过时兜底）与系统模态检测。
        // 注意它**不参与解闩**——稳态全屏下检测必然漏判，见类头注释。
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate(isSpaceChange: false) }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer

        evaluate(isSpaceChange: false)
    }

    public func stop() {
        isRunning = false
        if let observer = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        spaceObserver = nil
        watchdog?.invalidate()
        watchdog = nil
    }

    // MARK: - 评估

    // MARK: - 评估

    /// 闩锁动作：评估后对闩锁的处置
    enum LatchAction: Equatable {
        /// 不动
        case keep
        /// 有未决的复核则取消（进入动画余波）
        case cancelVerify
        /// 安排一次延迟复核（疑似退出全屏）
        case scheduleVerify
    }

    /// 闩锁决策（纯函数，可单测）。
    ///
    /// 规则：
    /// - 检测命中 → 置闩/保持；space 变化中的命中若非首次置位，视为「疑似退出动画」，安排复核；
    /// - space 变化的 miss：置位后 `echoGraceInterval` 内视为进入动画余波，不解闩；
    ///   超过宽限期则安排复核；
    /// - **非 space 变化的 miss 永不解闩**（稳态全屏下检测必然漏判，见类头注释）。
    nonisolated static func latchTransition(
        wasLatched: Bool,
        latchSetAt: Date,
        now: Date,
        detected: Bool,
        isSpaceChange: Bool,
        echoGraceInterval: TimeInterval
    ) -> (latched: Bool, action: LatchAction) {
        if detected {
            if !wasLatched {
                return (true, .cancelVerify)
            }
            if isSpaceChange, now.timeIntervalSince(latchSetAt) > echoGraceInterval {
                // 闩已在上、space 又变化、检测仍为真：大概率是退出动画
                return (true, .scheduleVerify)
            }
            return (true, .cancelVerify)
        }
        if isSpaceChange, wasLatched {
            if now.timeIntervalSince(latchSetAt) <= echoGraceInterval {
                return (true, .cancelVerify)
            }
            return (true, .scheduleVerify)
        }
        return (wasLatched, .keep)
    }

    private func evaluate(isSpaceChange: Bool) {
        let detected = screenProvider?().map { Self.isFullScreenWindowActive(on: $0) } ?? false
        let now = Date()

        let (latched, action) = Self.latchTransition(
            wasLatched: fullScreenLatch,
            latchSetAt: fullScreenLatchSetAt,
            now: now,
            detected: detected,
            isSpaceChange: isSpaceChange,
            echoGraceInterval: Self.echoGraceInterval
        )

        if latched, !fullScreenLatch {
            fullScreenLatchSetAt = now
        }
        fullScreenLatch = latched

        switch action {
        case .cancelVerify:
            clearVerifyWork?.cancel()
        case .scheduleVerify:
            scheduleClearVerify()
        case .keep:
            break
        }

        pushState()
    }

    /// 延迟一拍复核：等动画收尾后重新检测一次，仍检测不到全屏才真正解闩。
    private func scheduleClearVerify() {
        clearVerifyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let stillFullScreen = self.screenProvider?().map { Self.isFullScreenWindowActive(on: $0) } ?? false
            if !stillFullScreen {
                self.fullScreenLatch = false
                self.pushState()
            }
        }
        clearVerifyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clearVerifyDelay, execute: work)
    }

    /// 由闩锁 + 模态检测推导 blocker，变化时向外广播。
    private func pushState() {
        let next: Blocker
        if fullScreenLatch {
            next = .fullScreenApp
        } else if Self.isSystemModalPresent() {
            next = .systemModal
        } else {
            next = .none
        }
        guard next != blocker else { return }
        let previous = blocker
        blocker = next

        switch next {
        case .none:
            Log.layer.notice("层级守卫解除（原: \(String(describing: previous), privacy: .public)）")
        case .fullScreenApp:
            Log.layer.notice("检测到其他 App 全屏 → 让出并收起")
        case .systemModal:
            Log.layer.notice("检测到系统模态弹窗 → 临时降级 level，避免遮挡授权框")
        }

        onChange?(next)
    }

    // MARK: - 检测实现

    private static func windowList() -> [[String: Any]] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) else { return [] }
        return raw as? [[String: Any]] ?? []
    }

    /// CGWindowList 的坐标原点在主屏左上、y 向下；NSScreen 原点在主屏左下、y 向上。
    private static var mainScreenMaxY: CGFloat {
        NSScreen.screens.first?.frame.maxY ?? 0
    }

    private static func cgBounds(_ info: [String: Any]) -> CGRect? {
        guard let dict = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dict as CFDictionary)
    }

    /// 全屏检测：AX 窗口表为主、CGWindowList 形状为辅。
    /// 只在 space 切换瞬间被依赖是可靠的（见类头注释），稳态漏判由闩锁兜住。
    static func isFullScreenWindowActive(on screen: NSScreen) -> Bool {
        if axDetectsFullScreenWindow(on: screen) { return true }
        return cgShapeHeuristicMatches(on: screen)
    }

    /// 主路径：遍历普通应用的 AX 窗口，找 frame 恰好铺满目标屏幕的窗口。
    /// 注意稳态下全屏窗口在 AX 里报的是还原前 frame（会漏），依赖闩锁兜底。
    private static func axDetectsFullScreenWindow(on screen: NSScreen) -> Bool {
        let myPID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications {
            // 只看普通应用：本 App 是 accessory 天然被过滤，菜单栏小工具等不参与
            guard app.activationPolicy == .regular,
                  app.processIdentifier != myPID else { continue }
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            // 单应用 AX 查询限时：防止某个挂死的应用把主线程卡住
            AXUIElementSetMessagingTimeout(axApp, 0.4)
            guard let windows = axApp.elements(kAXWindowsAttribute as String) else { continue }
            for window in windows {
                guard let subrole = window.string(kAXSubroleAttribute as String), !subrole.isEmpty else { continue }
                guard let cgFrame = window.frame else { continue }
                let maxY = mainScreenMaxY
                let ns = CGRect(x: cgFrame.minX, y: maxY - cgFrame.maxY,
                                width: cgFrame.width, height: cgFrame.height)
                if ns.isApproximatelyEqual(to: screen.frame, tolerance: 2) {
                    Log.layer.notice(
                        "AX 检测到全屏窗口：app=\(app.localizedName ?? "?", privacy: .public) subrole=\(subrole, privacy: .public) frame=\(NSStringFromRect(cgFrame), privacy: .public)"
                    )
                    return true
                }
            }
        }
        return false
    }

    /// 兜底：属于其他进程的普通层可见窗口，是否正好铺满整块屏幕。
    /// 主要在进出全屏的动画瞬间命中（动画中的窗口暂具全屏形态）。
    private static func cgShapeHeuristicMatches(on screen: NSScreen) -> Bool {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let maxY = mainScreenMaxY

        for info in windowList() {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != myPID else { continue }
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0 else { continue }
            guard let cg = cgBounds(info) else { continue }

            let ns = CGRect(x: cg.minX, y: maxY - cg.maxY, width: cg.width, height: cg.height)
            if ns.isApproximatelyEqual(to: screen.frame, tolerance: 2) { return true }
        }
        return false
    }

    /// 系统模态弹窗检测：命中已知的系统进程名即认为需要让出层级。
    static func isSystemModalPresent() -> Bool {
        let myPID = ProcessInfo.processInfo.processIdentifier
        for info in windowList() {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != myPID else { continue }
            guard let owner = info[kCGWindowOwnerName as String] as? String else { continue }
            if systemModalOwners.contains(owner) { return true }
        }
        return false
    }
}

extension CGRect {
    /// 与另一矩形是否在容差内等价（全屏判定允许 1~2pt 的取整误差）
    func isApproximatelyEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
