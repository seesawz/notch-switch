import NotchKit
import SwiftUI

/// 刘海面板的内容：横向窗口预览条（Kimi 风格 + Liquid Glass）。
///
/// 可视区固定 4 张（PLAN.md §6.1），窗口多于 4 个时直接滚轮逐张滚动（§6.5）。
/// 材质统一走 `kimiGlass`（macOS 26+ Liquid Glass，低版本回退毛玻璃，见 KimiTheme）。
struct NotchRootView: View {

    @ObservedObject var permissions: PermissionsModel
    @ObservedObject var metrics: NotchMetrics
    @ObservedObject var windowList: WindowListModel
    @ObservedObject var thumbnails: ThumbnailStore
    @ObservedObject var selection: PanelSelection
    /// 用户在系统设置里的显示/辅助功能选项。材质与描边都由它决定，不在这里写死。
    @ObservedObject var display: SystemDisplayOptions

    var onActivate: (WindowInfo) -> Void

    private let cardWidth: CGFloat = 176
    private let cardImageHeight: CGFloat = 110
    private let cardSpacing: CGFloat = 12
    private let horizontalPadding: CGFloat = 16
    /// = 卡片 132 + 上下内边距 16（已移除 footer，见 §6.1）
    private let contentHeight: CGFloat = 148

    /// 预览带圆角：四角统一，由 `NSGlassEffectView` 以同一半径**原生**渲染（ADR-041）。
    /// 之前是「上平下圆」异形 + clipShape 硬裁，圆角处边缘光被切掉，背景看着像拼接。
    private let stripCornerRadius: CGFloat = 20

    private var stripShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: stripCornerRadius, style: .continuous)
    }

    private let cardImageShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    /// 悬停中的卡片（纯视觉反馈，不参与选中状态机）
    @State private var hoveredID: CGWindowID?

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 = 刘海（或菜单栏）本身占用的高度，必须完全透明。
            // 收起态时窗口被裁到只剩这一段，所以这里画任何东西都会露出来。
            Color.clear
                .frame(height: metrics.topInset)

            strip
                .frame(height: contentHeight, alignment: .top)
                // 内容跟随面板一起进出：淡入淡出 + 从顶边轻微缩放
                // （锚点取 .top，视觉上就是「从刘海长出来 / 收回去」）
                .opacity(metrics.isExpanded ? 1 : 0)
                .scaleEffect(metrics.isExpanded ? 1 : 0.97, anchor: .top)
                .animation(contentAnimation, value: metrics.isExpanded)
        }
        .frame(width: metrics.expandedSize.width,
               height: metrics.expandedSize.height,
               alignment: .top)
        .onAppear {
            selection.update(totalCount: windowList.windows.count)
        }
        .onChange(of: windowList.windows.count) { _, newCount in
            selection.update(totalCount: newCount)
        }
    }

    /// 内容动画曲线与 `NotchPanelController` 的窗口 frame 动画**同档位同曲线**，
    /// 否则「窗口在缩」和「内容在淡」会各走各的，看着发飘。
    private var contentAnimation: Animation {
        switch metrics.transition {
        case .expand: .easeOut(duration: metrics.transition.duration)
        case .collapseHover: .easeInOut(duration: metrics.transition.duration)
        case .collapseAction: .easeIn(duration: metrics.transition.duration)
        case .immediate: .linear(duration: 0)
        }
    }

    // MARK: - 预览带

    private var strip: some View {
        VStack(spacing: 0) {
            if windowList.windows.isEmpty {
                emptyState
            } else {
                cardRow
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 灵动岛式收起：内容在收起开始的**一帧内**消失，只留空玻璃胶囊缩回刘海。
        // 预览图跟着面板一起缩会在亮色窗口上闪白（实测），所以内容不参与收起动画；
        // 外层的淡出+缩放只作用于玻璃胶囊本身。
        .opacity(metrics.isExpanded ? 1 : 0)
        .animation(metrics.isExpanded ? contentAnimation : .linear(duration: 0), value: metrics.isExpanded)
        .kimiGlass(in: stripShape, display: display, cornerRadius: stripCornerRadius) {
            stripContent
        }
        .overlay {
            if display.increaseContrast {
                // 增强对比度（ADR-034 "bolder lines"）：全周加粗描边，轮廓处处可辨
                stripShape.strokeBorder(
                    Kimi.borderColor(contrast: true),
                    lineWidth: Kimi.borderWidth(contrast: true)
                )
            } else {
                // 常规态只描两侧+底部：顶边是玻璃与刘海/菜单栏的交界线，
                // 在那里描边等于在焊缝上再画一条线（ADR-041）；顶部轮廓交给玻璃自身 rim
                StripEdgeStroke(radius: stripCornerRadius)
                    .stroke(
                        Kimi.borderColor(contrast: false),
                        lineWidth: Kimi.borderWidth(contrast: false)
                    )
            }
        }
    }

    /// 预览带内容（嵌进玻璃 `contentView`，见 ADR-040）。
    private var stripContent: some View {
        VStack(spacing: 0) {
            if windowList.windows.isEmpty {
                emptyState
            } else {
                cardRow
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 灵动岛式收起：内容在收起开始的**一帧内**消失，只留空玻璃胶囊缩回刘海。
        // 预览图跟着面板一起缩会在亮色窗口上闪白（实测），所以内容不参与收起动画；
        // 外层的淡出+缩放只作用于玻璃胶囊本身。
        .opacity(metrics.isExpanded ? 1 : 0)
        .animation(metrics.isExpanded ? contentAnimation : .linear(duration: 0), value: metrics.isExpanded)
    }

    /// 只描「两侧 + 底部」的开口描边（ADR-041）：不闭口，顶边不画线。
    private struct StripEdgeStroke: Shape {
        var radius: CGFloat

        func path(in rect: CGRect) -> Path {
            let r = min(radius, rect.width / 2, rect.height / 2)
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
            p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                     startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
            p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                     startAngle: .degrees(90), endAngle: .degrees(0), clockwise: true)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + r))
            return p
        }
    }

    /// 所有卡片排成一长条，整体做水平位移。
    ///
    /// 为什么不「换一批卡片」：那样每次切换都是内容瞬变，无论帧率多高看起来都是「跳」。
    /// 排成一条 + 位移，配合 `PanelSelection` 的逐帧跟随，才有原生滚动的手感。
    private var cardRow: some View {
        HStack(spacing: cardSpacing) {
            ForEach(windowList.windows) { window in
                card(for: window)
            }
        }
        .padding(.horizontal, horizontalPadding)
        .offset(x: -selection.offset)
        .frame(width: metrics.expandedSize.width, alignment: .leading)
        .clipped()
    }

    private func card(for window: WindowInfo) -> some View {
        let hovered = hoveredID == window.id
        return Button {
            onActivate(window)
        } label: {
            VStack(spacing: 6) {
                thumbnail(for: window, hovered: hovered)
                titleRow(for: window)
            }
            .frame(width: cardWidth)
            .scaleEffect(hovered ? 1.03 : 1)
            .shadow(color: .black.opacity(hovered ? 0.22 : 0), radius: 10, y: 3)
            .animation(.spring(response: 0.24, dampingFraction: 0.75), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering {
                hoveredID = window.id
            } else if hoveredID == window.id {
                hoveredID = nil
            }
        }
        .help("\(window.appName) — \(window.displayTitle)")
    }

    @ViewBuilder
    private func thumbnail(for window: WindowInfo, hovered: Bool) -> some View {
        ZStack {
            if let image = thumbnails.images[window.id] {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: cardImageHeight)
                    .clipShape(cardImageShape)
            } else {
                fallbackThumbnail(for: window)
            }
        }
        .frame(width: cardWidth, height: cardImageHeight)
        .overlay {
            cardImageShape.strokeBorder(
                hovered ? Kimi.accent.opacity(0.85) : Kimi.borderColor(contrast: display.increaseContrast),
                lineWidth: Kimi.cardBorderWidth(hovered: hovered, contrast: display.increaseContrast)
            )
        }
        // 点击确认：先给一次「点中了」的反馈，面板再收起。
        // 没有这个的话，点击后面板直接缩回去，用户分不清是自己没点中还是已经生效了。
        .overlay {
            cardImageShape
                .strokeBorder(Kimi.accent, lineWidth: 2)
                .opacity(isActivating(window) ? 1 : 0)
        }
        .scaleEffect(isActivating(window) ? 0.955 : 1)
        .animation(.easeOut(duration: 0.09), value: selection.activatingWindowID)
        .overlay(alignment: .bottomLeading) {
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 14, height: 14)
                    .padding(5)
                    // 同源面材（ADR-041）：.ultraThinMaterial 是窗内采样材质，
                    // 叠在 Liquid Glass 上会显成灰色补丁；图标角标改用纯色低透明底
                    .background(
                        Color.black.opacity(0.45),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
                    .padding(6)
            }
        }
        .overlay(alignment: .topTrailing) {
            if window.isMinimized {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.white, .black.opacity(0.5))
                    .padding(6)
            }
        }
    }

    /// 没有缩略图时的降级显示（最小化窗口 / 尚未抓到 / 无屏幕录制权限）
    private func fallbackThumbnail(for window: WindowInfo) -> some View {
        ZStack {
            cardImageShape.fill(.linearGradient(
                colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.03)],
                startPoint: .top,
                endPoint: .bottom
            ))

            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 40, height: 40)
                    .opacity(0.85)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 26))
                    .foregroundStyle(.tertiary)
            }

            if thumbnails.isCapturing {
                ProgressView()
                    .controlSize(.small)
                    .offset(y: 30)
            }
        }
        .frame(width: cardWidth, height: cardImageHeight)
    }

    private func isActivating(_ window: WindowInfo) -> Bool {
        selection.activatingWindowID == window.id
    }

    private func titleRow(for window: WindowInfo) -> some View {
        HStack(spacing: 4) {
            Text(window.displayTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(window.showsPlaceholderTitle ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(width: cardWidth, alignment: .leading)
    }

    // MARK: - 空态与状态栏

    private var emptyState: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(permissions.accessibilityGranted
                    ? AnyShapeStyle(Color.primary.opacity(0.06))
                    : AnyShapeStyle(Kimi.accentGradient))

                Image(systemName: permissions.accessibilityGranted ? "macwindow.badge.plus" : "lock.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(permissions.accessibilityGranted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
            }
            .frame(width: 38, height: 38)

            Text(emptyHint)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: cardImageHeight + 22)
    }

    private var emptyHint: String {
        if !permissions.accessibilityGranted {
            return "未授予辅助功能权限，无法枚举窗口"
        }
        return "没有枚举到可切换的窗口"
    }
}
