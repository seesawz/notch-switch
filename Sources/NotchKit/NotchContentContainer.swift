import AppKit

/// 面板的内容容器。承担两件事：
///
/// 1. 让**固定尺寸**的内容视图始终「顶部居中」贴住面板上沿。
///    面板从刘海向外长大时，看到的是内容被逐层揭开，而不是内容被压缩重排。
///
/// 2. 捕获面板内的滚动事件（Shift + 滚轮翻卡，PLAN.md §6.5）。
///    为什么放在容器上而不是 SwiftUI 里：
///    SwiftUI 内容大多由 layer 绘制、没有独立的 NSView，滚动事件由 NSHostingView 收下后
///    沿响应者链上浮，最终会到达这里；而在 SwiftUI 里包一个 NSViewRepresentable
///    反而会被 NSHostingView 挡在中间。
public final class NotchContentContainer: NSView {

    /// 内容视图的最终尺寸（= 展开态尺寸）。
    public var contentSize: CGSize = .zero {
        didSet {
            needsLayout = true
            layoutContent()
        }
    }

    /// 滚动回调，参数是**内容位移量（点）**，已归一化。
    /// 注意这里给的是连续值不是「张数」——逐张步进在视觉上是瞬移，见 `ScrollFollow` 的说明。
    ///
    /// - Returns: 是否消费掉这次滚动。返回 `false` 时事件会继续传递，
    ///   这样「卡片不超过 4 张、没有可滚动内容」时不会白白吞掉用户的滚动。
    public var onScroll: ((CGFloat) -> Bool)?

    /// 已被处理的事件时间戳，用于与 local monitor 去重（同一个事件两条路径都会收到）
    public private(set) var lastHandledEventTimestamp: TimeInterval = -.greatestFiniteMagnitude

    public override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        layoutContent()
    }

    public override func layout() {
        super.layout()
        layoutContent()
    }

    public override func scrollWheel(with event: NSEvent) {
        if handleScrollEvent(event) { return }
        super.scrollWheel(with: event)
    }

    /// - Returns: 是否消费掉了这个事件
    @discardableResult
    public func handleScrollEvent(_ event: NSEvent) -> Bool {
        handleScroll(
            deltaX: event.scrollingDeltaX,
            deltaY: event.scrollingDeltaY,
            hasPreciseDeltas: event.hasPreciseScrollingDeltas,
            timestamp: event.timestamp
        )
    }

    /// 与 `handleScrollEvent` 等价，但只接受可跨隔离域传递的原始值。
    ///
    /// 为什么拆成两个：`NSEvent` 不是 Sendable，local monitor 回调是 nonisolated 的，
    /// 不能直接把 NSEvent 带进 MainActor 闭包。先取出需要的几个数值再进去即可。
    @discardableResult
    public func handleScroll(
        deltaX: CGFloat,
        deltaY: CGFloat,
        hasPreciseDeltas: Bool,
        timestamp: TimeInterval
    ) -> Bool {
        // 与另一条事件路径（local monitor / 响应者链）去重
        guard timestamp != lastHandledEventTimestamp else { return true }

        // 不再要求按住 Shift：普通滚轮、双指上下滑、双指左右滑、Shift+滚轮 都能翻卡。
        // stripOffset = 主导轴取值 + 量纲换算 + 方向取反（跟随系统滚动方向，ADR-024）
        let contentOffset = ScrollDelta.stripOffset(deltaX: deltaX, deltaY: deltaY, hasPreciseDeltas: hasPreciseDeltas)
        guard contentOffset != 0 else { return false }

        // 只有真的产生了滚动才消费事件；没有可滚动内容时让它继续传递
        guard onScroll?(contentOffset) == true else { return false }

        lastHandledEventTimestamp = timestamp
        return true
    }

    private func layoutContent() {
        guard let child = subviews.first else { return }
        // 水平居中、垂直顶对齐（坐标系原点在左下，所以 y = 容器高 − 内容高）
        child.frame = CGRect(
            x: (bounds.width - contentSize.width) / 2,
            y: bounds.height - contentSize.height,
            width: contentSize.width,
            height: contentSize.height
        )
    }
}
