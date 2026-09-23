import CoreGraphics
import Foundation

/// 滚动的跟随数学，纯值类型，可单测。
///
/// 为什么需要它：
/// 直接改索引（第 1 张 → 第 2 张）在视觉上是**瞬移**，无论帧率多高都是「跳」。
/// `offset` 每帧向 `target` 指数逼近，输入停下的瞬间仍有惯性收尾，而不是硬停。
///
/// 注意：**不做吸附**。滚到哪里就停在哪里，可以停在半张卡中间——
/// 强制对齐到卡片边界会在松手瞬间把内容再拽一下，反而破坏跟手感。
public struct ScrollFollow {

    /// 当前渲染偏移（点）
    public private(set) var offset: CGFloat = 0
    /// 目标偏移（点）
    public private(set) var target: CGFloat = 0

    /// 跟随时间常数（秒）。越小越跟手，越大越飘。
    ///
    /// 用**时间常数**而不是「每帧比例」：ProMotion 是 120Hz、普通屏是 60Hz，
    /// 固定每帧比例会让两种屏的滚动手感完全不同（120Hz 上会快一倍）。
    /// 0.035s ≈ 90% 在 80ms 内收敛，接近 macOS 原生滚动的阻尼感。
    public var timeConstant: TimeInterval = 0.035
    /// 小于该距离即认为稳定
    public var settleEpsilon: CGFloat = 0.4

    public init() {}

    /// 累加一次滚动输入（由调用方负责把 delta 缩放成点）
    public mutating func addInput(_ delta: CGFloat, maxOffset: CGFloat) {
        target = min(max(0, target + delta), maxOffset)
    }

    /// 窗口数量变化后收敛到合法范围
    public mutating func clamp(maxOffset: CGFloat) {
        target = min(max(0, target), maxOffset)
        offset = min(max(0, offset), maxOffset)
    }

    /// 推进一帧。
    /// - Parameter deltaTime: 距上一帧的实际时间，用来自适应屏幕刷新率
    /// - Returns: 是否仍在运动（false 表示可以停掉驱动定时器）
    public mutating func advance(deltaTime: TimeInterval = 1.0 / 60.0) -> Bool {
        guard deltaTime > 0 else { return true }
        let alpha = 1 - exp(-deltaTime / timeConstant)
        offset += (target - offset) * alpha
        if abs(target - offset) < settleEpsilon {
            offset = target
            return false
        }
        return true
    }

    public var isSettled: Bool { abs(target - offset) < settleEpsilon }

    /// 当前最接近的卡片索引（仅用于计算「可见区从第几张开始」，不会真的移动内容）
    public func anchorIndex(stride: CGFloat) -> Int {
        guard stride > 0 else { return 0 }
        return Int((offset / stride).rounded())
    }

    /// 键盘导航（F8）：把 `target` 夹进「第 `index` 张卡完整可见」的偏移区间。
    /// 已可见则原样返回（不产生多余滚动）；越界则贴到最近的边界。
    /// 区间：`upper = index×stride`（卡左缘不越出可视区左侧），
    /// `lower = (index+1−visibleCount)×stride`（卡右缘不越出右侧）。
    /// 基于 `target` 而非 `offset` 计算：连续按键时渲染还没追上，
    /// 用 offset 会拿旧位置做判断，快速连按会来回抖。
    public func targetToShow(index: Int, stride: CGFloat, visibleCount: Int, maxOffset: CGFloat) -> CGFloat {
        guard stride > 0, visibleCount > 0, index >= 0 else { return target }
        let lower = CGFloat(index + 1 - visibleCount) * stride
        let upper = CGFloat(index) * stride
        return min(max(0, min(max(target, lower), upper)), maxOffset)
    }

    public mutating func reset() {
        offset = 0
        target = 0
    }
}
