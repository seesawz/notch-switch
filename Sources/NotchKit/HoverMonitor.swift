import AppKit
import QuartzCore

/// 鼠标悬停监听（PLAN.md §4.5 / ADR-003）。
///
/// 为什么不用面板自己的 `NSTrackingArea`：
/// 收割鼠标事件的代价是「吞掉该区域的所有点击」。收起态的面板若接收事件，
/// 就会挡住菜单栏。所以改为：**面板完全不收事件，由全局监听判断进出热区**。
@MainActor
public final class HoverMonitor {

    /// 当前热区（屏幕坐标，原点左下）。切换收起/展开态时返回不同的矩形。
    public var hotZoneProvider: (() -> CGRect?)?
    public var onEnter: (() -> Void)?
    public var onLeave: (() -> Void)?

    private var isInside = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var safetyTimer: Timer?
    private var lastEventAt: CFTimeInterval = 0
    private var lastEvaluatedAt: CFTimeInterval = 0

    /// 事件节流：鼠标移动事件极其高频，不做节流会白白烧 CPU。
    private let throttle: CFTimeInterval = 1.0 / 60.0

    public init() {}

    public func start() {
        guard globalMonitor == nil else { return }

        // 全局监听：鼠标在**其他 App** 上时也能收到
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
        }

        // 本地监听：鼠标在我们**自己的面板**上时，全局监听收不到，必须补一个
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.handleMouseMoved() }
            return event
        }

        // 安全网：正常情况完全靠事件驱动，此定时器只为兜底「快速甩鼠标丢事件」的极端情况
        // （丢了事件会导致面板该收起时收不起来——这是最难受的 bug）
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.safetyTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
    }

    public func stop() {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        globalMonitor = nil
        localMonitor = nil
        safetyTimer?.invalidate()
        safetyTimer = nil
    }

    private func handleMouseMoved() {
        lastEventAt = CACurrentMediaTime()
        let now = lastEventAt
        guard now - lastEvaluatedAt >= throttle else { return }
        lastEvaluatedAt = now
        evaluate()
    }

    /// 仅在「超过 1.5s 没有收到任何鼠标事件」时才做一次校正，空闲时零开销。
    private func safetyTick() {
        guard CACurrentMediaTime() - lastEventAt > 1.5 else { return }
        evaluate()
    }

    private func evaluate() {
        guard let zone = hotZoneProvider?() else { return }
        let location = NSEvent.mouseLocation
        var inside = zone.contains(location)

        // 正在拖动其他窗口（按住左键）时不触发展开（ADR-030）：
        // 拖窗口经过刘海时面板突然弹出既挡视线，还可能吞掉松手点击造成误切换。
        // 只抑制「进入」：已展开态下的按住（比如正在点卡片）不能把面板收走，
        // 松手后下一次 mouseMoved 会正常判定进入。
        if inside, !isInside, NSEvent.pressedMouseButtons & 1 != 0 {
            inside = false
        }

        guard inside != isInside else { return }
        isInside = inside

        Log.hover.debug(
            """
            热区\(inside ? "进入" : "离开", privacy: .public) \
            鼠标=\(location.debugString, privacy: .public) \
            热区=\(zone.debugString, privacy: .public)
            """
        )

        if inside {
            onEnter?()
        } else {
            onLeave?()
        }
    }

    /// 供调试面板显示当前判定状态
    public var debugState: String {
        "isInside=\(isInside)  热区=\(hotZoneProvider?()?.debugString ?? "nil")  鼠标=\(NSEvent.mouseLocation.debugString)"
    }
}
