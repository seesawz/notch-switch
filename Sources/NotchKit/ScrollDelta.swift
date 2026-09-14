import CoreGraphics
import Foundation

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

    /// 用户的「自然滚动」设置（系统设置 → 鼠标/触控板；键 `com.apple.swipescrolldirection`，
    /// 出厂默认 = 开）。**方向必须以这个设置为依据，不靠猜**（ADR-024）。
    ///
    /// 这项设置的生效方式是：系统把它直接应用在派发给 App 的 `scrollingDelta` 上——
    /// 这是设置进入 App 的唯一通道（否则用户一切换设置，所有 App 的滚动都会反向）。
    /// 所以 `stripOffset` 的映射固定不变：delta 里已经带着用户设置的结果。
    /// 在这里再按设置键翻一次反而会双重翻转。读取它用于启动日志留痕，让方向行为可审计。
    public static var naturalScrollingEnabled: Bool {
        UserDefaults.standard.object(forKey: "com.apple.swipescrolldirection") as? Bool ?? true
    }

    /// 预览带的内容位移：主导轴换算 + 方向翻转（ADR-024）。
    ///
    /// NSEvent 的滚动 delta 遵循「**+ = 回退**」的约定（垂直 + = 向上滚 = 露出更早的内容，
    /// 水平 + = 向左滑同理）；符号已含 `naturalScrollingEnabled` 的结果。
    /// 预览带语义：「向下滚 / 向左滑 = 前进（露出后面的卡片）」，故整体取反一次。
    /// 用户切换系统滚动设置时，delta 符号随之翻转，预览带方向立即跟随。
    public static func stripOffset(deltaX: CGFloat, deltaY: CGFloat, hasPreciseDeltas: Bool) -> CGFloat {
        -contentOffset(for: dominant(deltaX: deltaX, deltaY: deltaY), hasPreciseDeltas: hasPreciseDeltas)
    }
}
