import AppKit

/// 层级守卫：维护「常驻最前台」这个承诺的**两个例外**（PLAN.md §4.1.1）。
///
/// - `fullScreenApp`：其他 App 进入全屏 → 我们主动收起（这就是需求里要的那个例外）
/// - `systemModal`：系统模态弹窗（授权框等）出现 → 我们临时降级 level 让出去。
///   这一条不做的话，level=1000 的面板会盖住授权按钮，用户点不到，流程直接卡死。
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

    public init() {}

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }

        // 低频看门狗：CGWindowList 调用很便宜，1Hz 的代价约等于零。
        // （全屏检测必须在收起态也生效，否则用户在全屏 App 里划到刘海时我们还会弹出来。）
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer

        evaluate()
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

    private func evaluate() {
        let next: Blocker
        if let screen = screenProvider?(), Self.isFullScreenWindowActive(on: screen) {
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

    /// 全屏检测：最前面的、属于其他进程的普通层窗口，是否正好铺满整块屏幕。
    ///
    /// 这是**启发式**实现。macOS 没有公开 API 能直接问「当前 Space 是不是全屏 Space」，
    /// 私有 `CGSSpaceGetType` 可作为后续增强（PLAN.md §4.1.1 第 5 条）。
    /// 之所以能用：普通窗口无法覆盖菜单栏区域，只有全屏窗口才可能与屏框完全重合。
    static func isFullScreenWindowActive(on screen: NSScreen) -> Bool {
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
