import AppKit
import ImageIO
import ScreenCaptureKit

/// 调试用：把面板所在屏幕区域截下来存成 PNG。
///
/// 为什么需要它：终端 / 编辑器进程通常**没有**屏幕录制权限（`screencapture` 会报
/// `could not create image from display`），但本 App 有。所以让 App 自己截图，
/// 排查视觉问题时就不用靠「用户描述 + 猜测」了。
///
/// 开法（改完需重启 App）：
/// ```
/// defaults write com.notchswitch.app NotchSwitch.capturePanelOnExpand -bool true
/// defaults delete com.notchswitch.app NotchSwitch.capturePanelOnExpand
/// ```
/// 产物固定写到 `/tmp/notchswitch-panel.png`。
enum PanelCapture {

    static let outputPath = "/tmp/notchswitch-panel.png"

    /// 展开 / 收起各截一张，用于对照「同样是这块屏幕，收起态长什么样」
    static func path(forExpanded expanded: Bool) -> String {
        expanded ? "/tmp/notchswitch-expanded.png" : "/tmp/notchswitch-collapsed.png"
    }

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "NotchSwitch.capturePanelOnExpand")
    }

    /// 把单张缩略图原样导出，用于判断「卡片上半发白」到底是图本身的问题还是叠加层的
    static var dumpsThumbnails: Bool {
        UserDefaults.standard.bool(forKey: "NotchSwitch.debugDumpThumbnail")
    }

    static func writePNG(_ image: CGImage, to path: String) {
        let url = URL(fileURLWithPath: path)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else { return }
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    /// 截取面板所在的那块屏幕区域（包含面板背后被采样的内容，
    /// 这样玻璃的透视效果才会真实呈现 —— 单窗口截图拿不到 backdrop）
    @MainActor
    static func capturePanelRegion(panelFrame: CGRect, expanded: Bool) {
        guard let display = NSScreen.notchTarget() else { return }

        // NSScreen 原点在左下，SCStreamConfiguration.sourceRect 用「显示器左上」为原点
        let screenHeight = display.frame.maxY
        var source = CGRect(
            x: panelFrame.minX - 60,
            y: screenHeight - panelFrame.maxY - 40,
            width: panelFrame.width + 120,
            height: panelFrame.height + 80
        )
        // 夹到屏幕内，越界会让截图整体偏移
        let screenRect = CGRect(origin: .zero, size: display.frame.size)
        source = source.intersection(screenRect)
        guard source.width > 10, source.height > 10 else { return }

        let scale = display.backingScaleFactor

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let scDisplay = content.displays.first else { return }

                let configuration = SCStreamConfiguration()
                configuration.sourceRect = source
                configuration.width = Int(source.width * scale)
                configuration.height = Int(source.height * scale)
                configuration.showsCursor = false
                configuration.captureResolution = .best

                let filter = SCContentFilter(display: scDisplay, excludingWindows: [])
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )

                let path = Self.path(forExpanded: expanded)
                Self.writePNG(image, to: path)
                Log.panel.notice("面板截图已写入 \(path, privacy: .public)")
            } catch {
                Log.panel.error("面板截图失败: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
