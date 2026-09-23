import Combine
import CoreGraphics
import Foundation

/// 预览带的「焦点」状态：哪张卡被聚焦（悬停或键盘选中）、大预览是否可见。
/// PLAN.md F4 / F8。
///
/// 两条进入路径：
/// - **鼠标**：悬停卡片 → `previewDelay`（280ms，§6.3）后弹出大预览；
///   换卡则重新计时。移出卡片只取消计时，**不**隐藏已显示的预览——
///   移到卡片间缝隙或预览卡本身时预览不该闪没。
/// - **键盘**：←→ 选中即显示，无延迟（F8「大预览跟随键盘选择」）。
///
/// 退出路径：滚动（§6.5「滚动期间抑制悬停大预览」）、面板收起（reset）。
@MainActor
public final class PanelFocus: ObservableObject {

    /// 当前聚焦的窗口（悬停目标或键盘选中项）。预览隐藏后仍保留，
    /// 键盘 ←→ 以它为基准继续移动。
    @Published public private(set) var focusedWindowID: CGWindowID?
    /// 大预览是否可见
    @Published public private(set) var isPreviewVisible = false

    /// 悬停多久后弹出大预览（PLAN.md §6.3：280ms）
    public var previewDelay: TimeInterval = 0.28

    private var hoverTask: Task<Void, Never>?
    /// 最近一次悬停的卡片。计时器到期时做一致性校验，防止过期任务误弹。
    private var hoveredID: CGWindowID?

    public init() {}

    // MARK: - 鼠标路径

    /// 鼠标进入某张卡片：启动（或重启）预览延迟计时。
    public func hover(_ id: CGWindowID) {
        hoverTask?.cancel()
        hoverTask = nil
        hoveredID = id
        let delay = previewDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.showPreview(ifHovering: id)
        }
    }

    /// 鼠标离开某张卡片：只在这张卡仍是「最近悬停」时才取消计时。
    ///
    /// 为什么带 id 校验：SwiftUI 的 onHover(false) 与下一张卡的 onHover(true)
    /// 顺序不保证，若无条件取消会把刚起好的计时一并取消。
    public func hoverEnded(_ id: CGWindowID) {
        guard hoveredID == id else { return }
        hoverTask?.cancel()
        hoverTask = nil
        hoveredID = nil
    }

    /// 取消悬停计时（滚动开始时调用）。已显示的预览由 `hidePreview` 负责。
    public func cancelHover() {
        hoverTask?.cancel()
        hoverTask = nil
        hoveredID = nil
    }

    /// 计时器到期：只有「仍是这张卡被悬停」时才弹（防过期任务）。
    private func showPreview(ifHovering id: CGWindowID) {
        guard hoveredID == id else { return }
        focusedWindowID = id
        isPreviewVisible = true
    }

    // MARK: - 键盘路径

    /// 键盘选中：立即聚焦并显示大预览，无延迟（F8）。
    public func select(_ id: CGWindowID) {
        cancelHover()
        focusedWindowID = id
        isPreviewVisible = true
    }

    // MARK: - 隐藏与复位

    /// 隐藏大预览（滚动 / Esc 第一档）。保留 focusedWindowID，键盘导航不受影响。
    public func hidePreview() {
        isPreviewVisible = false
    }

    /// 面板收起或聚焦窗口关闭时的整体复位。
    public func reset() {
        cancelHover()
        focusedWindowID = nil
        isPreviewVisible = false
    }
}
