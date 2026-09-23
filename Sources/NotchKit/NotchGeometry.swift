import AppKit

/// 刘海几何计算。
///
/// 全部做成纯函数，便于单元测试——`NSScreen` 无法在测试里伪造，
/// 但把输入参数抽出来后就可以用实测数据做断言（见 `NotchGeometryTests`）。
public enum NotchGeometry {

    /// 计算刘海矩形（屏幕坐标系，原点左下）。
    ///
    /// - Returns: `nil` 表示该屏幕没有刘海。
    ///
    /// 判据：`auxiliaryTopLeftArea` / `auxiliaryTopRightArea` 为 `nil` 即无刘海（macOS 12+）。
    /// 刘海宽度 = 屏宽 − 左区宽 − 右区宽。
    public static func notchFrame(
        screenFrame: CGRect,
        safeAreaTop: CGFloat,
        auxiliaryLeft: CGRect?,
        auxiliaryRight: CGRect?
    ) -> CGRect? {
        guard let left = auxiliaryLeft, let right = auxiliaryRight else { return nil }
        let width = screenFrame.width - left.width - right.width
        guard width > 0, safeAreaTop > 0 else { return nil }
        return CGRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.maxY - safeAreaTop,
            width: width,
            height: safeAreaTop
        )
    }

    /// 菜单栏高度（无刘海屏幕上的兜底参考值）。
    public static func menubarHeight(screenFrame: CGRect, visibleFrame: CGRect) -> CGFloat {
        max(screenFrame.maxY - visibleFrame.maxY, 0)
    }

    /// 卡片行 leading 内边距：右缘「露头」提示（R17 溢出发现性 / ADR-044）。
    ///
    /// 可视区固定 `visibleCount` 张（§6.1）。当窗口更多时，第 `visibleCount+1` 张
    /// 要在右缘露出 `peekWidth` 的窄条提示「右边还有」。offset=0 时第
    /// `visibleCount+1` 张卡的左缘位于 `padding + visibleCount × stride`，因此：
    /// ```
    /// padding = 展开宽度 − visibleCount × stride − peekWidth
    /// ```
    /// 标准展开宽 772：`772 − 4×188 − 12 = 8`。
    /// 窄外接屏上展开宽度不足时夹到 0，让裁切自然发生（不凑出负边距）。
    public static func cardRowLeadingPadding(
        expandedWidth: CGFloat,
        cardStride: CGFloat,
        visibleCount: Int,
        peekWidth: CGFloat
    ) -> CGFloat {
        max(0, expandedWidth - CGFloat(visibleCount) * cardStride - peekWidth)
    }
}

public extension NSScreen {

    /// 刘海矩形；`nil` 表示该屏幕无刘海。**运行时必须动态计算，不可硬编码尺寸。**
    var notchFrame: CGRect? {
        NotchGeometry.notchFrame(
            screenFrame: frame,
            safeAreaTop: safeAreaInsets.top,
            auxiliaryLeft: auxiliaryTopLeftArea,
            auxiliaryRight: auxiliaryTopRightArea
        )
    }

    /// 菜单栏高度。
    var menubarHeight: CGFloat {
        NotchGeometry.menubarHeight(screenFrame: frame, visibleFrame: visibleFrame)
    }

    var hasNotch: Bool { notchFrame != nil }

    /// 本项目需要关注的那块屏幕：优先带刘海的内建屏，否则退回主屏。
    ///
    /// 注意：**不能用 `NSScreen.main`**——它指的是「当前 key window 所在屏」，
    /// 不一定是带刘海的内建屏（多显示器时经常不是）。
    static func notchTarget() -> NSScreen? {
        NSScreen.screens.first(where: { $0.notchFrame != nil }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}

extension CGRect {
    /// 统一的一行式格式化，日志与调试面板共用，避免各处精度不一致
    public var debugString: String {
        String(format: "(%.1f, %.1f, %.1f, %.1f)", minX, minY, width, height)
    }
}

extension CGPoint {
    public var debugString: String {
        String(format: "(%.1f, %.1f)", x, y)
    }
}
