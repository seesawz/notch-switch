import AppKit
import Combine
import ScreenCaptureKit

/// 窗口缩略图（PLAN.md §4.4）。
///
/// 设计取舍：**事件驱动缓存，不做持续 SCStream**。
/// 持续抓流会让笔记本续航和温度都变差，而面板绝大多数时间是收起的。
/// 展开时先用缓存立刻出图，缺的异步补拍。
@MainActor
public final class ThumbnailStore: ObservableObject {

    @Published public private(set) var images: [CGWindowID: CGImage] = [:]
    @Published public private(set) var isCapturing = false
    @Published public private(set) var lastError: String?

    /// 缓存上限（PLAN.md §4.10 内存预算）
    public var maxCacheCount = 32
    /// 缩略图宽度（像素）：卡片 176pt 宽，Retina 下取 352
    private let thumbnailPixelWidth = 352

    private var recency: [CGWindowID] = []
    private var captureTask: Task<Void, Never>?

    public init() {}

    /// 请求补齐缺失的缩略图。已有缓存的不重复抓。
    public func refresh(for windows: [WindowInfo]) {
        purge(keeping: Set(windows.map(\.id)))

        let missing = windows.filter { images[$0.id] == nil }
        guard !missing.isEmpty else { return }
        guard captureTask == nil else { return }

        captureTask = Task { [weak self] in
            await self?.capture(missing)
            self?.captureTask = nil
        }
    }

    public func invalidate(_ windowID: CGWindowID) {
        images.removeValue(forKey: windowID)
        recency.removeAll { $0 == windowID }
    }

    public func invalidateAll() {
        images.removeAll()
        recency.removeAll()
    }

    // MARK: - 捕获

    private func capture(_ windows: [WindowInfo]) async {
        isCapturing = true
        defer { isCapturing = false }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            lastError = "无法获取可捕获窗口：\(error.localizedDescription)"
            Log.panel.error("ScreenCaptureKit 不可用：\(error.localizedDescription, privacy: .public)")
            return
        }

        let byID = Dictionary(content.windows.map { ($0.windowID, $0) }, uniquingKeysWith: { first, _ in first })

        for window in windows {
            // 捕获之间让出主线程，避免展开/滚动动画掉帧
            await Task.yield()
            guard let scWindow = byID[window.id] else { continue }
            guard let image = await capture(scWindow) else { continue }
            store(image, for: window.id)
        }

        lastError = nil
        Log.panel.debug("缩略图补齐完成，缓存 \(self.images.count) 张")
    }

    private func capture(_ window: SCWindow) async -> CGImage? {
        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return nil }

        let configuration = SCStreamConfiguration()
        configuration.width = thumbnailPixelWidth
        configuration.height = max(Int(Double(thumbnailPixelWidth) * (frame.height / frame.width)), 1)
        configuration.showsCursor = false

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)

        // 调试：导出一张原始缩略图，用于判断卡片发白是图本身的问题还是叠加层的
        if let image, PanelCapture.dumpsThumbnails {
            PanelCapture.writePNG(image, to: "/tmp/notchswitch-thumb.png")
            Log.panel.notice(
                """
                缩略图已导出: 窗口 \(window.windowID, privacy: .public) \
                原始 \(Int(frame.width), privacy: .public)x\(Int(frame.height), privacy: .public) \
                抓取 \(configuration.width, privacy: .public)x\(configuration.height, privacy: .public)
                """
            )
        }
        return image
    }

    // MARK: - 缓存

    private func store(_ image: CGImage, for id: CGWindowID) {
        images[id] = image
        recency.removeAll { $0 == id }
        recency.insert(id, at: 0)
        trim()
    }

    private func trim() {
        while recency.count > maxCacheCount, let last = recency.last {
            recency.removeLast()
            images.removeValue(forKey: last)
        }
    }

    private func purge(keeping valid: Set<CGWindowID>) {
        for id in Array(images.keys) where !valid.contains(id) {
            images.removeValue(forKey: id)
        }
        recency.removeAll { !valid.contains($0) }
    }
}
