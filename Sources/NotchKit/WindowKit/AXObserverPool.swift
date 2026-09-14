import AppKit
import ApplicationServices

/// 把非 Sendable 的 AXUIElement 跨隔离域传递用的显式逃生舱。
///
/// AX 的 C 回调是 nonisolated 的，但我们要在 MainActor 上处理；
/// `AXUIElement` 不是 Sendable，Swift 6 会拦截。这个类型的正确性前提是：
/// AX 回调本身就在主线程执行（我们把 RunLoopSource 加到了 main run loop）。
private struct UncheckedAXElement: @unchecked Sendable {
    let value: AXUIElement
}

/// C 回调入口。AXObserver 的回调必须是纯 C 函数指针，不能是方法。
private func notchAXObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ context: UnsafeMutableRawPointer?
) {
    guard let context else { return }
    let pool = Unmanaged<AXObserverPool>.fromOpaque(context).takeUnretainedValue()
    let name = notification as String
    let boxed = UncheckedAXElement(value: element)

    // AX 回调运行在 main run loop 上，因此这里 assumeIsolated 是安全的
    MainActor.assumeIsolated {
        pool.handle(notification: name, element: boxed.value)
    }
}

/// 按应用订阅 AX 通知，驱动 MRU 列表（PLAN.md §4.3）。
///
/// 关键设计：**完全不轮询**。窗口增删与焦点变化全部由 AX 回调驱动，
/// 空闲时 CPU 占用为零。节流合并交给上层的 WindowListModel。
@MainActor
public final class AXObserverPool {

    /// 焦点/主窗口变化 —— 这类事件要立即重排（用户直接感知）
    public var onFocusChanged: ((AXUIElement) -> Void)?
    /// 窗口增删、最小化等 —— 可以走节流
    public var onListChanged: (() -> Void)?

    /// 需要立即重排的通知
    private static let focusNotifications: Set<String> = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXApplicationActivatedNotification,
    ]

    private static let observedNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXApplicationActivatedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private var observers: [pid_t: AXObserver] = [:]

    public init() {}

    public var observedProcessCount: Int { observers.count }

    /// 让订阅集合与当前运行的应用集合对齐
    public func sync(with pids: Set<pid_t>) {
        let observed = Set(observers.keys)
        for pid in observed.subtracting(pids) {
            removeObserver(for: pid)
        }
        for pid in pids.subtracting(observed) {
            addObserver(for: pid)
        }
    }

    public func stop() {
        for pid in Array(observers.keys) {
            removeObserver(for: pid)
        }
    }

    fileprivate func handle(notification: String, element: AXUIElement) {
        if Self.focusNotifications.contains(notification) {
            onFocusChanged?(element)
        } else {
            onListChanged?()
        }
    }

    private func addObserver(for pid: pid_t) {
        var observer: AXObserver?
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard AXObserverCreate(pid, notchAXObserverCallback, &observer) == .success,
              let observer else { return }

        let axApp = AXUIElementCreateApplication(pid)
        for notification in Self.observedNotifications {
            _ = AXObserverAddNotification(observer, axApp, notification as CFString, context)
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func removeObserver(for pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}
