import Combine
import QuartzCore

/// 预览带的水平位移（PLAN.md §6.5）。
///
/// 渲染方式是「所有卡片排成一长条 + 整体位移」，而不是「换一批卡片」——
/// 后者天生是瞬移，无论怎么调都「跳」。配合 `ScrollFollow` 的逐帧跟随与松手吸附，
/// 才有原生滚动那种丝滑感。
@MainActor
public final class PanelSelection: ObservableObject {

    /// 当前渲染偏移（点）。视图用 `offset(x: -offset)` 直接消费。
    @Published public private(set) var offset: CGFloat = 0

    /// 刚刚被点击的卡片。用于在面板收起前给一次「点中了」的视觉确认——
    /// 否则点击后面板直接缩回去，用户不知道是自己没点中还是已经生效了。
    @Published public private(set) var activatingWindowID: CGWindowID?

    /// 可视卡片数（固定 4，PLAN.md §6.1 / ADR-009）
    public let visibleCount: Int
    /// 每张卡占用的水平步距 = 卡片宽 + 间距
    public let cardStride: CGFloat

    private var follow = ScrollFollow()
    private var ticker: Timer?
    private var totalCount = 0

    /// 驱动帧的定时器间隔。取 120Hz：ProMotion 上是帧对齐的，普通屏上多出来的几次
    /// tick 只是空转（每次仅做几次浮点运算），代价可以忽略。
    private let tickInterval: TimeInterval = 1.0 / 120.0

    private var lastTickAt: CFTimeInterval = 0

    public init(visibleCount: Int = 4, cardStride: CGFloat = 188) {
        self.visibleCount = visibleCount
        self.cardStride = cardStride
    }

    /// 最大位移：最后一批卡片刚好贴齐
    public var maxOffset: CGFloat {
        max(0, CGFloat(max(0, totalCount - visibleCount)) * cardStride)
    }

    /// 当前第一个可见窗口的索引。
    /// **F8 预留**（键盘/大预览导航未实现，PLAN.md §6.6）：目前只有单测在消费它。
    public var firstVisibleIndex: Int {
        guard totalCount > 0 else { return 0 }
        return min(max(0, follow.anchorIndex(stride: cardStride)), totalCount - 1)
    }

    /// **F8 预留**（同 `firstVisibleIndex`）。
    public var visibleRange: Range<Int> {
        let start = firstVisibleIndex
        return start..<min(totalCount, start + visibleCount)
    }

    // MARK: - 输入

    /// 窗口数量变化时同步（新增/关闭窗口后要靠它收敛边界）
    public func update(totalCount: Int) {
        self.totalCount = totalCount
        follow.clamp(maxOffset: maxOffset)
        offset = follow.offset
    }

    /// 连续滚动输入。`delta` 已经是「内容位移点数」（由 `ScrollDelta` 换算）。
    public func scroll(by delta: CGFloat, totalCount: Int) {
        self.totalCount = totalCount
        follow.addInput(delta, maxOffset: maxOffset)
        startTicking()
    }

    /// 逐张步进（**F8 预留**：键盘 / 以后的大预览导航用）
    public func step(_ direction: Int, totalCount: Int) {
        scroll(by: CGFloat(direction) * cardStride, totalCount: totalCount)
    }

    /// 键盘导航（F8）：确保第 `index` 张卡完整可见。已可见则不动（不产生多余位移）。
    /// 位移走 `scroll(by:)` 的帧同步跟随，所以是平滑滚动而不是瞬移。
    public func ensureVisible(index: Int, totalCount: Int) {
        self.totalCount = totalCount
        let desired = follow.targetToShow(
            index: index,
            stride: cardStride,
            visibleCount: visibleCount,
            maxOffset: maxOffset
        )
        let delta = desired - follow.target
        guard abs(delta) > 0.5 else { return }
        scroll(by: delta, totalCount: totalCount)
    }

    public func reset() {
        follow.reset()
        offset = 0
        activatingWindowID = nil
        stopTicking()
    }

    /// 标记某张卡被点击（切换后的确认高亮）
    public func markActivating(_ windowID: CGWindowID) {
        activatingWindowID = windowID
    }

    /// 清除确认高亮。只有当前高亮的仍是这张卡时才清，
    /// 避免「连点两张卡时前一张的定时器把后一张的高亮清掉」。
    public func clearActivating(_ windowID: CGWindowID) {
        guard activatingWindowID == windowID else { return }
        activatingWindowID = nil
    }

    // MARK: - 帧驱动

    private func startTicking() {
        guard ticker == nil else { return }
        lastTickAt = CACurrentMediaTime()
        let timer = Timer(timeInterval: tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    /// 由定时器驱动的一帧：dt 取真实经过时间，保证不同刷新率下手感一致
    func tick() {
        let now = CACurrentMediaTime()
        let deltaTime = lastTickAt == 0 ? tickInterval : now - lastTickAt
        lastTickAt = now
        tick(deltaTime: deltaTime)
    }

    /// 单帧推进（可指定 dt，供测试同步收敛）
    func tick(deltaTime: TimeInterval) {
        // 没有任何吸附：追上目标就停在哪，可以停在半张卡中间
        let isMoving = follow.advance(deltaTime: deltaTime)

        if offset != follow.offset { offset = follow.offset }
        if !isMoving { stopTicking() }
    }

    /// 仅供测试：以固定 dt 立刻推进到静止状态
    func settleImmediately() {
        for _ in 0..<1000 {
            tick(deltaTime: 1.0 / 60.0)
            if ticker == nil { break }
        }
    }
}
