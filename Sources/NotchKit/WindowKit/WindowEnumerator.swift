import AppKit
import ApplicationServices

/// 窗口枚举（PLAN.md §4.2）：**AX 为主，CG 为辅**。
///
/// - AX 提供：可操作句柄、标题、最小化状态、位置尺寸
/// - CG 提供：窗口几何/层级过滤，以及（私有 API 不可用时的）CGWindowID 匹配
@MainActor
public enum WindowEnumerator {

    /// 小于这个尺寸的「窗口」基本都是辅助元素，不是用户认知里的窗口
    private static let minimumSize = CGSize(width: 80, height: 60)

    public static func enumerate() -> [WindowInfo] {
        let myPID = ProcessInfo.processInfo.processIdentifier
        let snapshots = CGWindowSnapshot.snapshot()
        let normalSnapshots = snapshots.filter(\.isNormalLayer)

        var result: [WindowInfo] = []

        for app in NSWorkspace.shared.runningApplications {
            // 只关心「常规」应用：排除菜单栏程序、后台代理
            guard app.activationPolicy == .regular else { continue }
            let pid = app.processIdentifier
            guard pid != myPID else { continue }

            let axApp = AXUIElementCreateApplication(pid)
            guard let axWindows = axApp.elements(kAXWindowsAttribute as String) else { continue }

            for axWindow in axWindows {
                guard let info = makeWindowInfo(
                    axWindow: axWindow,
                    app: app,
                    pid: pid,
                    snapshots: normalSnapshots
                ) else { continue }
                result.append(info)
            }
        }

        // 按 CGWindowList 的前后顺序排序，作为冷启动的初始顺序（MRUOrder 随后会覆盖它）
        let frontToBack = Dictionary(
            uniqueKeysWithValues: snapshots.enumerated().map { ($0.element.id, $0.offset) }
        )
        return result.sorted { lhs, rhs in
            (frontToBack[lhs.id] ?? Int.max) < (frontToBack[rhs.id] ?? Int.max)
        }
    }

    private static func makeWindowInfo(
        axWindow: AXUIElement,
        app: NSRunningApplication,
        pid: pid_t,
        snapshots: [CGWindowSnapshot]
    ) -> WindowInfo? {
        // 只保留标准窗口，排除浮动面板、弹出层等。
        // subrole 必须严格等于 AXStandardWindow：**为 nil 的也要挡**——
        // 实测访达会多报一个全屏桌面元素（subrole=nil、frame 盖住整个桌面），
        // 不挡就会多出一张卡片（2026-09-14 实测复现）。
        guard axWindow.string(kAXSubroleAttribute as String) == (kAXStandardWindowSubrole as String) else {
            return nil
        }

        guard let frame = axWindow.frame, frame.width >= minimumSize.width, frame.height >= minimumSize.height else {
            return nil
        }

        // 优先用私有 API 精确映射；不可用时按「pid + 位置」近似匹配
        let windowID = AXWindowID.windowID(of: axWindow)
            ?? matchSnapshot(pid: pid, frame: frame, snapshots: snapshots)?.id
        guard let windowID else { return nil }

        return WindowInfo(
            id: windowID,
            pid: pid,
            bundleID: app.bundleIdentifier,
            appName: app.localizedName ?? "未知应用",
            axElement: axWindow,
            title: axWindow.string(kAXTitleAttribute as String) ?? "",
            isMinimized: axWindow.bool(kAXMinimizedAttribute as String) ?? false,
            frame: frame,
            appIcon: app.icon
        )
    }

    /// 私有 API 不可用时的兜底：同 pid 下位置最接近的那个窗口
    private static func matchSnapshot(
        pid: pid_t,
        frame: CGRect,
        snapshots: [CGWindowSnapshot]
    ) -> CGWindowSnapshot? {
        snapshots
            .filter { $0.pid == pid }
            .min { lhs, rhs in
                abs(lhs.bounds.minX - frame.minX) + abs(lhs.bounds.minY - frame.minY)
                    < abs(rhs.bounds.minX - frame.minX) + abs(rhs.bounds.minY - frame.minY)
            }
    }
}
