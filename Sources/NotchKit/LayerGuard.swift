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
///
/// ── 检测在后台线程执行（ADR-042）──
///
/// AX 检测要对每个常规应用做多次 Mach IPC（读窗口表、subrole、frame），
/// 单应用还设了 0.4s 的 messaging timeout——一个挂死的应用就能把调用方卡住几百毫秒。
/// 检测本身不碰 UI，放主线程纯属浪费：现在主线程每拍只做**廉价的取值**
/// （NSScreen frame、常规应用 pid 列表，无 IPC），AX/CG 查询全部丢进
/// `Task.detached`，结果回主线程后走同一套闩锁决策（`latchTransition` 不变，单测钉死）。
/// 在途检测用「合并队列」去重：同时只会有一发检测，迟到的请求按优先级
/// （space 变化 > 复核 > 看门狗）合并成一次。
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
    nonisolated static let systemModalOwners: Set<String> = [
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

    // MARK: 异步检测管线（ADR-042）

    /// 一次检测需要的全部输入。**在主线程采集**（都是廉价的本地读取，无 IPC），
    /// 传给后台任务使用——`NSScreen` / `NSWorkspace` 本身不是线程安全的，不能跨线程碰。
    private struct DetectionContext: Sendable {
        let myPID: pid_t
        /// 主屏在 NSScreen 坐标系里的 maxY（CG 坐标 → NSScreen 坐标换算用）
        let mainScreenMaxY: CGFloat
        /// 关注屏幕的 frame（NSScreen 坐标系）。`.zero` 表示当前没有屏幕可对比。
        let targetScreenFrame: CGRect
        /// 常规应用的 pid 列表（AX 检测只看这些）
        let regularAppPIDs: [pid_t]
    }

    /// 一次检测的结果。检测器只回答「是/否」，决策全在主线程。
    private struct DetectionResult: Sendable {
        let fullScreen: Bool
        let systemModal: Bool
    }

    /// 检测请求的种类。`clearVerify` 有独占语义（只有它能解闩），
    /// 其余走 `latchTransition`。
    private enum RequestKind: Equatable {
        case evaluate(isSpaceChange: Bool)
        case clearVerify

        /// 合并优先级：在途检测没回来时，新请求与排队请求按此合并，
        /// 高优先级覆盖低优先级。space 变化最关键不能丢；
        /// 复核是「确认退出全屏」的专项，比一次普通看门狗 tick 重要。
        var priority: Int {
            switch self {
            case .evaluate(true): 2
            case .clearVerify: 1
            case .evaluate(false): 0
            }
        }
    }

    /// 是否有一发检测在后台执行
    private var detectionInFlight = false
    /// 在途期间的合并请求（至多一个）
    private var queuedRequest: RequestKind?

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
        // 检测本体在后台线程（ADR-042），主线程每拍只做廉价取值。
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
        clearVerifyWork?.cancel()
        clearVerifyWork = nil
        queuedRequest = nil
        detectionInFlight = false
    }

    // MARK: - 评估

    /// 评估入口：主线程只采集廉价输入，检测本体在后台执行（ADR-042）。
    private func evaluate(isSpaceChange: Bool) {
        submit(.evaluate(isSpaceChange: isSpaceChange))
    }

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

    /// 提交一次检测请求。已有检测在途时合并进队列，保证：
    /// ① 同时只有一发检测（结果不会乱序覆盖）；② space 变化永不丢失。
    private func submit(_ kind: RequestKind) {
        guard isRunning else { return }

        if detectionInFlight {
            switch queuedRequest {
            case let queued? where kind.priority <= queued.priority:
                break   // 已排队请求优先级更高或相同（先到先得），丢弃新请求
            default:
                queuedRequest = kind
            }
            return
        }

        detectionInFlight = true
        let context = captureContext()
        Task.detached(priority: .utility) { [weak self] in
            let result = Self.performDetection(context: context)
            await MainActor.run { [weak self] in
                guard let self, self.isRunning else { return }
                self.detectionInFlight = false
                self.apply(kind: kind, result: result)
                if let next = self.queuedRequest {
                    self.queuedRequest = nil
                    self.submit(next)
                }
            }
        }
    }

    /// 主线程采集检测输入。全部是本地读取：`NSScreen.screens`、
    /// `runningApplications` 的 pid 过滤，没有任何 IPC。
    private func captureContext() -> DetectionContext {
        DetectionContext(
            myPID: ProcessInfo.processInfo.processIdentifier,
            mainScreenMaxY: NSScreen.screens.first?.frame.maxY ?? 0,
            targetScreenFrame: screenProvider?()?.frame ?? .zero,
            regularAppPIDs: NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .map(\.processIdentifier)
        )
    }

    /// 检测完成后的落地：按请求种类套用闩锁决策，再广播状态。
    private func apply(kind: RequestKind, result: DetectionResult) {
        switch kind {
        case .evaluate(let isSpaceChange):
            let now = Date()
            let (latched, action) = Self.latchTransition(
                wasLatched: fullScreenLatch,
                latchSetAt: fullScreenLatchSetAt,
                now: now,
                detected: result.fullScreen,
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

        case .clearVerify:
            // 复核是唯一能解闩的路径：等动画收尾后仍检测不到全屏才真正解闩。
            // 复核仍检测到全屏（退出动画未结束 / 又进去了）→ 不动，等下一次。
            if !result.fullScreen {
                fullScreenLatch = false
            }
        }

        pushState(systemModal: result.systemModal)
    }

    /// 延迟一拍复核：等动画收尾后重新检测一次，仍检测不到全屏才真正解闩。
    private func scheduleClearVerify() {
        clearVerifyWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.submit(.clearVerify)
        }
        clearVerifyWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.clearVerifyDelay, execute: work)
    }

    /// 由闩锁 + 模态检测推导 blocker，变化时向外广播。
    private func pushState(systemModal: Bool) {
        let next: Blocker
        if fullScreenLatch {
            next = .fullScreenApp
        } else if systemModal {
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

    // MARK: - 检测实现（nonisolated：在后台任务中执行，不碰 UI）

    nonisolated private static func windowList() -> [[String: Any]] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) else { return [] }
        return raw as? [[String: Any]] ?? []
    }

    /// 全屏检测：AX 窗口表为主、CGWindowList 形状为辅。
    /// 只在 space 切换瞬间被依赖是可靠的（见类头注释），稳态漏判由闩锁兜住。
    nonisolated private static func isFullScreenActive(context: DetectionContext) -> Bool {
        if axDetectsFullScreenWindow(context: context) { return true }
        return cgShapeHeuristicMatches(context: context)
    }

    /// 主路径：遍历普通应用的 AX 窗口，找 frame 恰好铺满目标屏幕的窗口。
    /// 注意稳态下全屏窗口在 AX 里报的是还原前 frame（会漏），依赖闩锁兜底。
    nonisolated private static func axDetectsFullScreenWindow(context: DetectionContext) -> Bool {
        for pid in context.regularAppPIDs {
            guard pid != context.myPID else { continue }
            let axApp = AXUIElementCreateApplication(pid)
            // 单应用 AX 查询限时：防止某个挂死的应用把检测卡死。
            // （检测在后台线程，超时最多拖慢下一拍，不再阻塞主线程。）
            AXUIElementSetMessagingTimeout(axApp, 0.4)
            guard let windows = axApp.elements(kAXWindowsAttribute as String) else { continue }
            for window in windows {
                guard let subrole = window.string(kAXSubroleAttribute as String), !subrole.isEmpty else { continue }
                guard let cgFrame = window.frame else { continue }
                let ns = CGRect(x: cgFrame.minX, y: context.mainScreenMaxY - cgFrame.maxY,
                                width: cgFrame.width, height: cgFrame.height)
                if ns.isApproximatelyEqual(to: context.targetScreenFrame, tolerance: 2) {
                    Log.layer.notice(
                        "AX 检测到全屏窗口：pid=\(pid, privacy: .public) subrole=\(subrole, privacy: .public) frame=\(NSStringFromRect(cgFrame), privacy: .public)"
                    )
                    return true
                }
            }
        }
        return false
    }

    /// 兜底：属于其他进程的普通层可见窗口，是否正好铺满整块屏幕。
    /// 主要在进出全屏的动画瞬间命中（动画中的窗口暂具全屏形态）。
    nonisolated private static func cgShapeHeuristicMatches(context: DetectionContext) -> Bool {
        for info in windowList() {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != context.myPID else { continue }
            guard let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue, layer == 0 else { continue }
            guard (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0 else { continue }
            guard let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict as CFDictionary) else { continue }

            let ns = CGRect(x: cg.minX, y: context.mainScreenMaxY - cg.maxY, width: cg.width, height: cg.height)
            if ns.isApproximatelyEqual(to: context.targetScreenFrame, tolerance: 2) { return true }
        }
        return false
    }

    /// 系统模态弹窗检测：命中已知的系统进程名即认为需要让出层级。
    nonisolated private static func isSystemModalPresent(myPID: pid_t) -> Bool {
        for info in windowList() {
            guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != myPID else { continue }
            guard let owner = info[kCGWindowOwnerName as String] as? String else { continue }
            if systemModalOwners.contains(owner) { return true }
        }
        return false
    }

    /// 后台检测入口：一次跑完全屏检测与模态检测。
    nonisolated private static func performDetection(context: DetectionContext) -> DetectionResult {
        DetectionResult(
            fullScreen: isFullScreenActive(context: context),
            systemModal: isSystemModalPresent(myPID: context.myPID)
        )
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
