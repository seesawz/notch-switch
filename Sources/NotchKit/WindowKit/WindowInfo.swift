import AppKit
import ApplicationServices

/// 一个可切换的窗口（PLAN.md §5.4）。
public struct WindowInfo: Identifiable {

    /// CGWindowID —— 同时是 ScreenCaptureKit 截图时的唯一标识
    public let id: CGWindowID
    public let pid: pid_t
    public let bundleID: String?
    public let appName: String
    /// 可操作句柄：切换窗口时要用它
    public let axElement: AXUIElement
    public var title: String
    public var isMinimized: Bool
    public var frame: CGRect
    public var appIcon: NSImage?

    public init(
        id: CGWindowID,
        pid: pid_t,
        bundleID: String?,
        appName: String,
        axElement: AXUIElement,
        title: String,
        isMinimized: Bool,
        frame: CGRect,
        appIcon: NSImage?
    ) {
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.axElement = axElement
        self.title = title
        self.isMinimized = isMinimized
        self.frame = frame
        self.appIcon = appIcon
    }

    /// 没有标题时（未授予屏幕录制权限的常见情况）用应用名兜底
    public var displayTitle: String {
        title.isEmpty ? appName : title
    }

    /// 没有标题且拿不到标题时，用它在同应用多窗口间区分
    public var showsPlaceholderTitle: Bool { title.isEmpty }
}

extension WindowInfo: Hashable {
    public static func == (lhs: WindowInfo, rhs: WindowInfo) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
