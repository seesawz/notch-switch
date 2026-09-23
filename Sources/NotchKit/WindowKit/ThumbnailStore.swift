import AppKit
import Combine
import ScreenCaptureKit

/// 窗口缩略图（PLAN.md §4.4）。
///
/// 设计取舍：**事件驱动缓存，不做持续 SCStream**。
/// 持续抓流会让笔记本续航和温度都变差，而面板绝大多数时间是收起的。
/// 展开时先用缓存立刻出图，缺的异步补拍。
///
/// 新鲜度（ADR-043）：缓存图带抓取时间，超过 `staleInterval` 视为过期——
/// 否则已缓存的图永不更新，窗口内容变了卡片还停在旧帧（甚至停在启动那一刻）。
/// 重抓时机沿用 ADR-033 的结论：**只在面板不可见时抓**（收起后 0.35s），
/// 抓取全程后台执行，不与展开/滚动动画抢主线程。
@MainActor
public final class ThumbnailStore: ObservableObject {

    @Published public private(set) var images: [CGWindowID: CGImage] = [:]
    @Published public private(set) var isCapturing = false
    @Published public private(set) var lastError: String?

    /// 缓存上限（PLAN.md §4.10 内存预算）
    public var maxCacheCount = 32
    /// 缩略图多旧算过期（秒）。收起后的补拍会重抓「缺失 + 过期」的窗口。
    /// 置 0 = 每次补拍都全量重抓（面板快速开关也不会反复抓，因为请求只在收起时来）。
    public var staleInterval: TimeInterval = 10
    /// 缩略图宽度（像素）。卡片 176pt 在 2x 屏需 352；取一倍的压缩不够大预览用，
    /// 故取 704（= 2× 卡片宽 = 1.1× 预览最大宽 640pt）：卡片与大预览共用同一份图，
    /// 不另存第二套。32 张 × ~1.2MB ≈ 40MB，仍在 §4.10 的 64MB 缓存预算内（ADR-045）。
    private let thumbnailPixelWidth = 704

    private var recency: [CGWindowID] = []
    /// 每张缓存图的抓取时刻，与 `images` 同步增删
    private var capturedAt: [CGWindowID: Date] = [:]
    private var captureTask: Task<Void, Never>?
    /// 抓取进行中收到的最新补拍请求。任务结束后用它再跑一轮，
    /// 不再像以前那样直接丢弃（旧逻辑下启动瞬间开新窗口会白卡到下次收起）。
    private var pendingRefreshWindows: [WindowInfo]?

    public init() {}

    /// 请求补齐缺失 / 过期的缩略图。
    public func refresh(for windows: [WindowInfo]) {
        purge(keeping: Set(windows.map(\.id)))

        let now = Date()
        let missing = windows.filter {
            Self.needsCapture(
                hasImage: images[$0.id] != nil,
                capturedAt: capturedAt[$0.id],
                now: now,
                staleInterval: staleInterval
            )
        }
        guard !missing.isEmpty else { return }
        guard captureTask == nil else {
            pendingRefreshWindows = windows
            return
        }
        startCapture(missing)
    }

    /// 某窗口此刻是否需要（重新）抓图。纯函数，可单测。
    ///
    /// 没抓过 → 要；抓过但已超过 `staleInterval` → 也要（窗口内容早变了，
    /// 卡片不能永远停在旧帧，见 ADR-043）。
    nonisolated static func needsCapture(
        hasImage: Bool,
        capturedAt: Date?,
        now: Date,
        staleInterval: TimeInterval
    ) -> Bool {
        if !hasImage { return true }
        guard let capturedAt else { return true }
        return now.timeIntervalSince(capturedAt) >= staleInterval
    }

    public func invalidate(_ windowID: CGWindowID) {
        images.removeValue(forKey: windowID)
        capturedAt.removeValue(forKey: windowID)
        recency.removeAll { $0 == windowID }
    }

    // MARK: - 捕获

    private func startCapture(_ windows: [WindowInfo]) {
        captureTask = Task { [weak self] in
            await self?.capture(windows)
            guard let self else { return }
            self.captureTask = nil
            // 抓取期间来过新请求 → 用最新的窗口列表再补一轮
            if let pending = self.pendingRefreshWindows {
                self.pendingRefreshWindows = nil
                self.refresh(for: pending)
            }
        }
    }

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

        var failures = 0
        for window in windows {
            // 捕获之间让出主线程，避免展开/滚动动画掉帧
            await Task.yield()
            guard let scWindow = byID[window.id] else {
                failures += 1
                continue
            }
            guard let image = await capture(scWindow) else {
                failures += 1
                continue
            }
            store(image, for: window.id)
        }

        // 部分失败也要留痕——以前最后一律清空 lastError，失败时用户无从得知
        if failures > 0 {
            lastError = "\(failures) 个窗口缩略图抓取失败"
            Log.panel.error("缩略图补齐：\(failures, privacy: .public)/\(windows.count, privacy: .public) 失败")
        } else {
            lastError = nil
        }
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
        capturedAt[id] = Date()
        recency.removeAll { $0 == id }
        recency.insert(id, at: 0)
        trim()
    }

    private func trim() {
        while recency.count > maxCacheCount, let last = recency.last {
            recency.removeLast()
            images.removeValue(forKey: last)
            capturedAt.removeValue(forKey: last)
        }
    }

    private func purge(keeping valid: Set<CGWindowID>) {
        for id in Array(images.keys) where !valid.contains(id) {
            images.removeValue(forKey: id)
            capturedAt.removeValue(forKey: id)
        }
        recency.removeAll { !valid.contains($0) }
    }
}
