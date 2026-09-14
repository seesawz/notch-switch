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

    /// 可视卡片数（固定 4，PLAN.md §6.1 / ADR-009）
    public let visibleCount: Int
    /// 每张卡占用的水平步距 = 卡片宽 + 间距
    public let cardStride: CGFloat

    private var follow = ScrollFollow()
    private var ticker: Timer?
    private var lastInputAt: CFTimeInterval = 0
    private var needsSnap = false
    private var totalCount = 0

    /// 驱动帧的定时器间隔。取 120Hz：ProMotion 上是帧对齐的，普通屏上多出来的几次
    /// tick 只是空转（每次仅做几次浮点运算），代价可以忽略。
    private let tickInterval: TimeInterval = 1.0 / 120.0
    /// 停止输入多久后开始吸附。测试里会设为 0 以便同步收敛。
    public var settleDelay: TimeInterval = 0.12

    private var lastTickAt: CFTimeInterval = 0

    public init(visibleCount: Int = 4, cardStride: CGFloat = 188) {
        self.visibleCount = visibleCount
        self.cardStride = cardStride
    }

    /// 最大位移：最后一批卡片刚好贴齐
    public var maxOffset: CGFloat {
        max(0, CGFloat(max(0, totalCount - visibleCount)) * cardStride)
    }

    /// 当前第一个可见窗口的索引
    public var firstVisibleIndex: Int {
        guard totalCount > 0 else { return 0 }
        return min(max(0, follow.anchorIndex(stride: cardStride)), totalCount - 1)
    }

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
        lastInputAt = CACurrentMediaTime()
        needsSnap = true
        startTicking()
    }

    /// 逐张步进（键盘 / 以后的大预览导航用）
    public func step(_ direction: Int, totalCount: Int) {
        scroll(by: CGFloat(direction) * cardStride, totalCount: totalCount)
    }

    public func reset() {
        follow.reset()
        needsSnap = false
        offset = 0
        stopTicking()
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
        var isMoving = follow.advance(deltaTime: deltaTime)

        // 已经追上目标、且输入停了足够久 → 吸附到最近的卡片边界
        if !isMoving, needsSnap, CACurrentMediaTime() - lastInputAt > settleDelay {
            needsSnap = false
            isMoving = follow.snap(to: cardStride, maxOffset: maxOffset)
        }

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
