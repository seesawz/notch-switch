import CoreGraphics
import Foundation

/// 滚动的「跟随 + 吸附」数学，纯值类型，可单测。
///
/// 为什么需要它：
/// 直接改索引（第 1 张 → 第 2 张）在视觉上是**瞬移**，无论帧率多高都是「跳」。
/// 要做到丝滑，需要：
///  1. `offset` 每帧向 `target` 指数逼近 —— 输入停下的瞬间仍有惯性收尾，不是硬停
///  2. 松手后吸附到最近的卡片边界 —— 保证最终停位整齐，而不是卡在半张卡中间
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

    /// 吸附到最近的卡片边界。
    /// - Returns: 是否产生了新的目标位置（true 表示还要继续动）
    public mutating func snap(to stride: CGFloat, maxOffset: CGFloat) -> Bool {
        guard stride > 0 else { return false }
        let snapped = min(max(0, (offset / stride).rounded() * stride), maxOffset)
        guard abs(snapped - offset) > settleEpsilon else { return false }
        target = snapped
        return true
    }

    public var isSettled: Bool { abs(target - offset) < settleEpsilon }

    /// 当前对齐到的卡片索引
    public func anchorIndex(stride: CGFloat) -> Int {
        guard stride > 0 else { return 0 }
        return Int((offset / stride).rounded())
    }

    public mutating func reset() {
        offset = 0
        target = 0
    }
}
