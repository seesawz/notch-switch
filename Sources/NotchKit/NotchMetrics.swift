import Combine
import Foundation

/// 面板几何的「对外广播」。
///
/// SwiftUI 内容需要知道自己该留出多少顶部透明区，但这些值由
/// `NotchPanelController` 在运行时算出来，而视图又必须先于控制器创建。
/// 用一个 ObservableObject 把两者解耦。
@MainActor
public final class NotchMetrics: ObservableObject {

    /// 内容顶部的透明留白 = max(刘海高度, 菜单栏高度)。
    /// 收起态时面板只剩刘海那一条，这块留白保证不会漏出任何内容。
    @Published public private(set) var topInset: CGFloat = 33
    /// 展开后的面板尺寸
    @Published public private(set) var expandedSize: CGSize = CGSize(width: 772, height: 181)
    /// 当前屏幕是否有刘海
    @Published public private(set) var hasNotch: Bool = true

    /// 面板当前是否展开。SwiftUI 内容用它做淡入淡出与缩放。
    @Published public private(set) var isExpanded: Bool = false
    /// 本次变化使用的动画档位，供 SwiftUI 侧对齐曲线
    @Published public private(set) var transition: PanelTransition = .expand

    /// 大预览是否可见（F4）。与 isExpanded 分开：预览的显隐不该触发预览带重播淡入。
    @Published public private(set) var isPreviewVisible: Bool = false
    /// 大预览使面板内容增高的总量（间隙 + 卡高，`LargePreviewLayout.panelExtraHeight`）。
    /// 视图用它撑高内容 frame，与控制器的窗口 frame 同源。
    @Published public private(set) var previewExtraHeight: CGFloat = 0
    /// 预览显隐动画档位，与窗口 frame 动画对齐（同 ADR-027「两边同档位同曲线」的道理）
    @Published public private(set) var previewTransition: PanelTransition = .expand

    public init() {}

    func update(topInset: CGFloat, expandedSize: CGSize, hasNotch: Bool) {
        if self.topInset != topInset { self.topInset = topInset }
        if self.expandedSize != expandedSize { self.expandedSize = expandedSize }
        if self.hasNotch != hasNotch { self.hasNotch = hasNotch }
    }

    /// 先设档位再设状态，保证 SwiftUI 在**同一次**更新里同时看到两者，
    /// 否则会先用上一档的曲线播一次，出现半帧的曲线错配。
    func setExpanded(_ expanded: Bool, transition: PanelTransition) {
        if self.transition != transition { self.transition = transition }
        if self.isExpanded != expanded { self.isExpanded = expanded }
    }

    /// 大预览显隐（同上：先档位后状态）。值不变时不赋值，避免无谓的广播。
    func setPreview(visible: Bool, extraHeight: CGFloat, transition: PanelTransition) {
        if self.previewTransition != transition { self.previewTransition = transition }
        if self.isPreviewVisible != visible { self.isPreviewVisible = visible }
        if self.previewExtraHeight != extraHeight { self.previewExtraHeight = extraHeight }
    }
}
