import CoreGraphics
import Foundation

/// 大预览浮层的几何（PLAN.md §6.1 / F4）。纯函数，可单测。
///
/// 大预览是 F4 的核心差异点：悬停卡片 280ms（或键盘 ←→ 选中）后，
/// 预览带下方长出一张预览卡——按窗口原始宽高比缩放的大图（最大 640×400pt）
/// 加一行信息（标题 / 应用名 / 最小化标记 / ✕ 关闭）。
///
/// 布局决策（ADR-045）：预览卡与预览带同处一个面板窗口，面板高度随之增长，
/// 不开第二个窗口——层级、key 状态（液态玻璃的前提，ADR-037）、热区、收起
/// 逻辑全部天然复用，避免第二套窗口生命周期。
public enum LargePreviewLayout {

    /// 大图的最大显示尺寸（pt）
    public static let maxImageSize = CGSize(width: 640, height: 400)
    /// 大图下方信息行高度
    public static let infoRowHeight: CGFloat = 34
    /// 大图与信息行的间距
    public static let contentSpacing: CGFloat = 8
    /// 预览卡内边距（上下左右）
    public static let contentPadding: CGFloat = 12
    /// 预览卡与上方预览带的间距
    public static let gapBelowStrip: CGFloat = 10
    /// 预览卡圆角：与预览带一致（同族观感，且 Liquid Glass 分支由玻璃原生渲染）
    public static let cornerRadius: CGFloat = 20
    /// 窗口 frame 异常（≤0 / 非有限）时的回退宽高比（16:10，主流屏比例）
    public static let defaultAspect: CGFloat = 16.0 / 10.0

    /// 按窗口宽高比算大图的显示尺寸：完整放进 `maxImageSize`，比例不变。
    public static func displaySize(aspect: CGFloat) -> CGSize {
        let a = (aspect.isFinite && aspect > 0) ? aspect : defaultAspect
        let width = min(maxImageSize.width, maxImageSize.height * a)
        return CGSize(width: width, height: width / a)
    }

    /// 预览卡外框尺寸 = 大图 + 内边距×2 + 信息行 + 间距
    public static func cardSize(image displaySize: CGSize) -> CGSize {
        CGSize(
            width: displaySize.width + contentPadding * 2,
            height: displaySize.height + infoRowHeight + contentSpacing + contentPadding * 2
        )
    }

    /// 面板内容需要为此预览卡增加的总高度 = 预览带与卡片之间的间隙 + 卡高。
    /// 控制器与 SwiftUI 视图都只消费这一个值，两边不会各算各的。
    public static func panelExtraHeight(cardHeight: CGFloat) -> CGFloat {
        gapBelowStrip + cardHeight
    }

    /// 一步到位：由窗口宽高比得到面板内容增高。
    public static func panelExtraHeight(windowAspect: CGFloat) -> CGFloat {
        panelExtraHeight(cardHeight: cardSize(image: displaySize(aspect: windowAspect)).height)
    }
}
