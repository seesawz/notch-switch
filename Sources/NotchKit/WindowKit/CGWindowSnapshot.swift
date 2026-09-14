import AppKit

/// CGWindowList 的一条快照。
///
/// 用途有两个：
///  1. 冷启动时的初始 MRU 顺序（CGWindowList 是前后排列的）
///  2. 私有 API `_AXUIElementGetWindow` 不可用时，按「pid + 位置」把 AX 窗口匹配到 CGWindowID
public struct CGWindowSnapshot {

    public let id: CGWindowID
    public let pid: pid_t
    /// 全局坐标，原点在主屏左上（与 AX 的 position 同一坐标系，可直接比较）
    public let bounds: CGRect
    public let layer: Int
    public let alpha: Double

    public var isNormalLayer: Bool { layer == 0 && alpha > 0 }

    public init(id: CGWindowID, pid: pid_t, bounds: CGRect, layer: Int, alpha: Double) {
        self.id = id
        self.pid = pid
        self.bounds = bounds
        self.layer = layer
        self.alpha = alpha
    }

    /// 前台到后台的顺序（CGWindowList 本身的返回顺序）
    public static func snapshot() -> [CGWindowSnapshot] {
        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else { return [] }

        return raw.compactMap { info in
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let alpha = (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue
            else { return nil }

            return CGWindowSnapshot(id: id, pid: pid, bounds: bounds, layer: layer, alpha: alpha)
        }
    }
}
