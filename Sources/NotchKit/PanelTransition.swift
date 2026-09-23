import CoreGraphics
import Foundation

/// 面板展开 / 收起的动画档位。
///
/// 三档存在的理由：**收起重在「让开」**。用户已经做完决定了，
/// 面板应该迅速消失，而不是慢慢缩回去慢慢消失。
/// 所以「点击卡片之后」要比「鼠标移开」更快、更干脆、曲线更偏加速。
public enum PanelTransition: Equatable {
    /// 展开：从刘海往外长，稍慢一点才有「长出来」的感觉
    case expand
    /// 鼠标移开后的自动收起：常规节奏
    case collapseHover
    /// 点击卡片后的收起：短促、加速，明确表示「我收到了，马上让开」
    case collapseAction
    /// 立刻收起，不做动画（切屏、失焦等场景）
    case immediate

    public var duration: TimeInterval {
        switch self {
        case .expand: 0.22
        case .collapseHover: 0.20
        case .collapseAction: 0.14
        case .immediate: 0
        }
    }

    /// 三次贝塞尔控制点（与 `NSAnimationContext.timingFunction` 共用）
    public var controlPoints: (x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat) {
        switch self {
        case .expand:
            // 缓出：起手快、落位稳
            (0.32, 0.0, 0.24, 1.0)
        case .collapseHover:
            (0.40, 0.0, 0.20, 1.0)
        case .collapseAction:
            // 缓入：越收越快，像被吸回刘海里
            (0.45, 0.0, 0.75, 0.0)
        case .immediate:
            (0.0, 0.0, 1.0, 1.0)
        }
    }

    /// 内容是否应该在这一档里淡出。
    ///
    /// ⚠️ 历史 API：v0.17 改「灵动岛式收起」后，内容在收起开始的**一帧内**消失，
    /// 不再参与任何收起动画（见 NotchRootView.stripContent）。此属性已与实际行为脱节，
    /// 仅存留以兼容旧单测断言，新代码不得依赖。
    public var animatesContent: Bool { self != .immediate }
}
