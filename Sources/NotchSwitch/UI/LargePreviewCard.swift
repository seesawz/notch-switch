import AppKit
import NotchKit
import SwiftUI

/// 大预览浮层（F4 / ADR-045）：出现在预览带下方，展示聚焦窗口的大图与信息行。
///
/// 结构：大图（按窗口原始宽高比缩放，最大 640×400）+ 一行信息
/// （应用图标 / 标题 / 应用名 / 最小化标记 / ✕ 关闭）。
/// 材质走 `kimiGlass`（与预览带同一套系统：Liquid Glass / 毛玻璃 / 不透明降级），
/// 圆角由玻璃原生渲染（ADR-041）。
struct LargePreviewCard: View {
    let window: WindowInfo
    /// 缓存的缩略图。没有时降级为「应用图标大占位」——最小化窗口
    /// 本就抓不到图（R3），启动初期也可能还没补拍完。
    let image: CGImage?
    let isCapturing: Bool
    @ObservedObject var display: SystemDisplayOptions

    var onClose: () -> Void

    private let cardShape = RoundedRectangle(
        cornerRadius: LargePreviewLayout.cornerRadius,
        style: .continuous
    )
    private let imageShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    private var displaySize: CGSize {
        LargePreviewLayout.displaySize(
            aspect: window.frame.height > 0
                ? window.frame.width / window.frame.height
                : LargePreviewLayout.defaultAspect
        )
    }

    var body: some View {
        let cardSize = LargePreviewLayout.cardSize(image: displaySize)
        // kimiGlass 不消费被修饰视图（与 NotchRootView.strip 同一个维护陷阱）：
        // 必须 Color.clear 占位、把内容放进闭包
        Color.clear
            .frame(width: cardSize.width, height: cardSize.height)
            .kimiGlass(in: cardShape, display: display, cornerRadius: LargePreviewLayout.cornerRadius) {
                VStack(spacing: LargePreviewLayout.contentSpacing) {
                    imageArea
                    infoRow
                }
                .padding(LargePreviewLayout.contentPadding)
            }
            .overlay {
                // 自由浮层（不贴刘海），全周描边；粗细跟随「增强对比度」（ADR-034）
                cardShape.strokeBorder(
                    Kimi.borderColor(contrast: display.increaseContrast),
                    lineWidth: Kimi.borderWidth(contrast: display.increaseContrast)
                )
            }
    }

    // MARK: - 大图

    @ViewBuilder
    private var imageArea: some View {
        ZStack {
            if let image {
                Image(decorative: image, scale: 2)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: displaySize.width, height: displaySize.height)
            } else {
                placeholder
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
        .clipShape(imageShape)
        .overlay {
            imageShape.strokeBorder(
                Kimi.borderColor(contrast: display.increaseContrast),
                lineWidth: Kimi.borderWidth(contrast: display.increaseContrast)
            )
        }
    }

    /// 无图占位：保持与大图同样的比例（面板高度不因抓图缺失而跳动）
    private var placeholder: some View {
        ZStack {
            imageShape.fill(.linearGradient(
                colors: [Color.primary.opacity(0.08), Color.primary.opacity(0.03)],
                startPoint: .top,
                endPoint: .bottom
            ))

            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .opacity(0.85)
            } else {
                Image(systemName: "macwindow")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
            }

            if isCapturing {
                ProgressView()
                    .controlSize(.small)
                    .offset(y: 44)
            }
        }
    }

    // MARK: - 信息行

    private var infoRow: some View {
        HStack(spacing: 6) {
            if let icon = window.appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 16, height: 16)
            }

            Text(window.displayTitle)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            // 标题拿不到（无屏幕录制权限）时 displayTitle 已回退应用名，
            // 只有「标题与应用名不同」才补一次应用名，避免重复
            if !window.showsPlaceholderTitle {
                Text(window.appName)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            if window.isMinimized {
                Image(systemName: "minus.circle")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .help("该窗口已最小化")
            }

            Spacer(minLength: 8)

            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("关闭窗口")
        }
        .frame(height: LargePreviewLayout.infoRowHeight)
    }
}
