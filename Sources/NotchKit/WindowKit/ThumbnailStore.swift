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
///
/// 内存纪律（v1.0.7）：① 只存「卡片实际显示的那块」——卡片是 16:10 中心裁切
/// （SwiftUI `.fill` 的效果），存储也裁到同一区域，竖长窗口不再存整幅
/// （此前 9:16 竖窗会存 352×626，是实际需要的 2.8 倍）；② 存储前重画成
/// 紧凑位图，释放 ScreenCaptureKit 返回图的 IOSurface 背载；③ 单张恒为
/// 352×220×4 ≈ 300KB，上限 32 张 ≈ 9.6MB，预算可精确计算；④ 订阅系统内存
/// 压力，告急时全量释放（纯缓存，下次收起后重抓即可）。
@MainActor
public final class ThumbnailStore: ObservableObject {

    @Published public private(set) var images: [CGWindowID: CGImage] = [:]
    @Published public private(set) var isCapturing = false
    @Published public private(set) var lastError: String?

    /// 缓存上限（PLAN.md §4.10 内存预算）。单张恒为 352×220×4 ≈ 300KB
    /// （紧凑位图），32 张封顶 ≈ 9.6MB；日常随窗口数走，`purge` 会清掉已关窗口。
    public var maxCacheCount = 32
    /// 缩略图多旧算过期（秒）。收起后的补拍会重抓「缺失 + 过期」的窗口。
    /// 置 0 = 每次补拍都全量重抓（面板快速开关也不会反复抓，因为请求只在收起时来）。
    public var staleInterval: TimeInterval = 10
    /// 缩略图存储尺寸（像素）：卡片 176×110pt（16:10）在 Retina 2x 下的大小。
    /// 抓图仍按窗口原始比例抓，入库前中心裁切到这个尺寸（见 `cardCroppedBitmap`）。
    private let thumbnailPixelWidth = 352
    private let thumbnailPixelHeight = 220

    /// 系统内存压力源：warning 时缓存减半，critical 时全量释放。
    /// 缩略图是纯缓存（丢了下次收起自动重抓），是全 App 最该先让路的内存。
    private var pressureSource: DispatchSourceMemoryPressure?

    private var recency: [CGWindowID] = []
    /// 每张缓存图的抓取时刻，与 `images` 同步增删
    private var capturedAt: [CGWindowID: Date] = [:]
    private var captureTask: Task<Void, Never>?
    /// 抓取进行中收到的最新补拍请求。任务结束后用它再跑一轮，
    /// 不再像以前那样直接丢弃（旧逻辑下启动瞬间开新窗口会白卡到下次收起）。
    private var pendingRefreshWindows: [WindowInfo]?

    public init() {
        installPressureHandling()
    }

    /// 取消内存压力监听（进程退出时调用；Agent App 常驻，正常不触发）。
    public func stop() {
        pressureSource?.cancel()
        pressureSource = nil
    }

    private func installPressureHandling() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.handleMemoryPressure(self.sourceData())
            }
        }
        source.resume()
        pressureSource = source
    }

    private func sourceData() -> DispatchSource.MemoryPressureEvent {
        pressureSource?.data ?? []
    }

    private func handleMemoryPressure(_ event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) {
            let freed = images.count
            purgeAll()
            // 把堆里的空闲页还给系统，footprint 立刻降
            malloc_zone_pressure_relief(malloc_default_zone(), 0)
            Log.panel.notice(
                "系统内存告急 → 缩略图全量释放（\(freed, privacy: .public) 张），占用 \(MemoryInfo.physicalFootprintDescription(), privacy: .public)"
            )
        } else if event.contains(.warning) {
            trimToRecentCount(maxCacheCount / 2)
            Log.panel.notice(
                "系统内存吃紧 → 缩略图缓存减半（剩 \(self.images.count, privacy: .public) 张），占用 \(MemoryInfo.physicalFootprintDescription(), privacy: .public)"
            )
        }
    }

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
            // 裁切 + 紧凑位图重画涉及 CoreFoundation 临时对象，池内及时释放
            let cropped = autoreleasepool { Self.cardCroppedBitmap(image, width: thumbnailPixelWidth, height: thumbnailPixelHeight) ?? image }
            store(cropped, for: window.id)
        }

        // 部分失败也要留痕——以前最后一律清空 lastError，失败时用户无从得知
        if failures > 0 {
            lastError = "\(failures) 个窗口缩略图抓取失败"
            Log.panel.error("缩略图补齐：\(failures, privacy: .public)/\(windows.count, privacy: .public) 失败")
        } else {
            lastError = nil
        }
        Log.panel.debug(
            "缩略图补齐完成，缓存 \(self.images.count) 张，进程占用 \(MemoryInfo.physicalFootprintDescription(), privacy: .public)"
        )
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

    // MARK: - 裁切与紧凑位图

    /// 把任意比例的抓取图转成「卡片实际显示的那块」的紧凑位图。
    ///
    /// 卡片用 `.aspectRatio(.fill)` + 固定 16:10 frame 显示——SwiftUI 只显示
    /// 源图的**中心 16:10 区域**，其余部分存在缓存里纯属浪费（竖窗最坏多存 2.8 倍）。
    /// 这里在入库前做同样的中心裁切（显示结果逐像素等价），并重画进
    /// `bytesPerRow = width×4` 的自建位图：ScreenCaptureKit 返回的图是
    /// IOSurface 背载（GPU 侧、带对齐冗余），重画后变成普通内存且随引用释放。
    ///
    /// 失败（极端尺寸等）返回 nil，调用方回退存原图——正确性优先于省内存。
    /// 纯函数，可单测。
    nonisolated static func cardCroppedBitmap(_ source: CGImage, width targetWidth: Int, height targetHeight: Int) -> CGImage? {
        guard targetWidth > 0, targetHeight > 0,
              source.width > 0, source.height > 0 else { return nil }

        let sourceAspect = CGFloat(source.width) / CGFloat(source.height)
        let targetAspect = CGFloat(targetWidth) / CGFloat(targetHeight)

        // 中心裁切窗口（与 SwiftUI .fill 的裁切一致：居中、保留尽可能大的区域）
        var cropWidth = source.width
        var cropHeight = source.height
        if sourceAspect > targetAspect {
            cropWidth = Int((CGFloat(source.height) * targetAspect).rounded())
        } else if sourceAspect < targetAspect {
            cropHeight = Int((CGFloat(source.width) / targetAspect).rounded())
        }
        guard cropWidth > 0, cropHeight > 0 else { return nil }
        let cropX = (source.width - cropWidth) / 2
        let cropY = (source.height - cropHeight) / 2

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth * 4,          // 紧凑行距，无对齐冗余
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let scale = CGFloat(targetWidth) / CGFloat(cropWidth)
        context.interpolationQuality = .high
        // 把源图画在「裁切窗口对齐目标画布」的位置：负偏移即中心裁切
        context.draw(
            source,
            in: CGRect(
                x: -CGFloat(cropX) * scale,
                y: -CGFloat(cropY) * scale,
                width: CGFloat(source.width) * scale,
                height: CGFloat(source.height) * scale
            )
        )
        return context.makeImage()
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

    /// 内存压力路径：全量释放。
    private func purgeAll() {
        images.removeAll()
        capturedAt.removeAll()
        recency.removeAll()
    }

    /// 内存压力路径：只留最近 `count` 张。
    private func trimToRecentCount(_ count: Int) {
        guard recency.count > count else { return }
        let dropped = recency.suffix(from: max(0, count))
        recency = Array(recency.prefix(max(0, count)))
        for id in dropped {
            images.removeValue(forKey: id)
            capturedAt.removeValue(forKey: id)
        }
    }
}
