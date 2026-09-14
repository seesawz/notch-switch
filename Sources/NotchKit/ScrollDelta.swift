import CoreGraphics

/// 滚动输入的归一化（PLAN.md §6.5）。
///
/// 需要抹平三类输入之间的差异：
///  1. **轴向**：普通滚轮给垂直 delta、双指左右滑给水平 delta、
///     Shift + 滚轮会被 macOS「转轴」成水平 delta。三种都要能翻卡。
///  2. **量纲**：触控板 `scrollingDeltaY` 是**点**（细碎连续），
///     机械滚轮的 `scrollingDeltaY` 是**行数**（通常一格 = 1）。两者相差一个数量级。
///  3. **单次幅度**：不同鼠标一格上报的行数不同（1 / 3 / 10 都有），要封顶。
public enum ScrollDelta {

    /// 机械滚轮「一行」折算成多少点（≈ 一行文字的高度）
    public static let pointsPerLine: CGFloat = 44
    /// 单次事件的最大位移，避免某些鼠标一格上报 10 行时一下跳掉两张卡
    public static let maxWheelStep: CGFloat = 120

    /// 取主导轴：绝对值大的那个。
    ///
    /// **不按 Shift 分情况**——因为三种输入都会自然落到「某个轴的绝对值明显更大」上：
    ///  - 普通滚轮 / 双指上下滑 → 垂直占优
    ///  - 双指左右滑 → 水平占优（横向浏览最自然的手势）
    ///  - Shift + 滚轮 → macOS 已把垂直映射成水平，水平占优
    public static func dominant(deltaX: CGFloat, deltaY: CGFloat) -> CGFloat {
        abs(deltaX) > abs(deltaY) ? deltaX : deltaY
    }

    /// 把原始 delta 换算成内容位移量（点）。
    ///
    /// - Parameter hasPreciseDeltas: `NSEvent.hasPreciseScrollingDeltas`
    ///   （触控板 / 带滚轮的鼠标为 true 还是 false 取决于驱动，不能靠设备类型猜）
    public static func contentOffset(for delta: CGFloat, hasPreciseDeltas: Bool) -> CGFloat {
        guard delta != 0 else { return 0 }

        // 触控板：1:1 跟手。任何缩放都会破坏「丝滑」，这里绝不能动。
        if hasPreciseDeltas { return delta }

        // 机械滚轮：delta 是行数，乘行高换算成点，再封顶
        let points = delta * pointsPerLine
        return max(-maxWheelStep, min(maxWheelStep, points))
    }
}
