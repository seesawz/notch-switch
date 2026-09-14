import NotchKit
import SwiftUI

/// 刘海面板的内容：横向窗口预览条。
///
/// 可视区固定 4 张（PLAN.md §6.1），窗口多于 4 个时用 Shift + 滚轮逐张滚动（§6.5）。
/// M4 待补：大预览浮层、键入搜索、应用筛选条。
struct NotchRootView: View {

    @ObservedObject var permissions: PermissionsModel
    @ObservedObject var metrics: NotchMetrics
    @ObservedObject var windowList: WindowListModel
    @ObservedObject var thumbnails: ThumbnailStore
    @ObservedObject var selection: PanelSelection

    var onActivate: (WindowInfo) -> Void

    private let cardWidth: CGFloat = 176
    private let cardImageHeight: CGFloat = 110
    private let cardSpacing: CGFloat = 12
    private let horizontalPadding: CGFloat = 16
    /// = 卡片 132 + 上下内边距 16（已移除 footer，见 §6.1）
    private let contentHeight: CGFloat = 148

    var body: some View {
        VStack(spacing: 0) {
            // 顶部 = 刘海（或菜单栏）本身占用的高度，必须完全透明。
            // 收起态时窗口被裁到只剩这一段，所以这里画任何东西都会露出来。
            Color.clear
                .frame(height: metrics.topInset)

            strip
                .frame(height: contentHeight, alignment: .top)
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
        .background {
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 18,
                bottomTrailingRadius: 18,
                topTrailingRadius: 0,
                style: .continuous
            )
            .fill(.ultraThinMaterial)
            .overlay {
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 18,
                    bottomTrailingRadius: 18,
                    topTrailingRadius: 0,
                    style: .continuous
                )
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
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
        Button {
            onActivate(window)
        } label: {
            VStack(spacing: 6) {
                thumbnail(for: window)
                titleRow(for: window)
            }
            .frame(width: cardWidth)
        }
        .buttonStyle(.plain)
        .help("\(window.appName) — \(window.displayTitle)")
    }

    @ViewBuilder
    private func thumbnail(for window: WindowInfo) -> some View {
        ZStack {
            if let image = thumbnails.images[window.id] {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: cardWidth, height: cardImageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                fallbackThumbnail(for: window)
            }
        }
        .frame(width: cardWidth, height: cardImageHeight)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
        }
        .overlay(alignment: .bottomLeading) {
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
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
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.07))

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
        VStack(spacing: 6) {
            Image(systemName: permissions.accessibilityGranted ? "macwindow.badge.plus" : "lock.fill")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
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
