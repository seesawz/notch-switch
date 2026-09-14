import os

/// 统一日志出口。
///
/// 面板类应用的很多问题（层级被压、热区不触发、全屏判定误报）在 UI 上看不出原因，
/// 只能靠日志定位。用 `os.Logger` 而不是 `print`，好处是不需要挂在终端上，
/// 可以直接 stream 一个已经在运行的实例。
///
/// 查看方式（**注意：zsh 里 `log` 是内建命令，必须写全路径 `/usr/bin/log`**）：
/// ```
/// # 重要事件（notice 以上，含展开/收起/层级变化）
/// /usr/bin/log stream --predicate 'subsystem == "com.notchswitch.app"'
///
/// # 含高频细节（悬停进出等 debug 级）
/// /usr/bin/log stream --debug --predicate 'subsystem == "com.notchswitch.app"'
///
/// # 回看最近 2 分钟
/// /usr/bin/log show --last 2m --debug --info --predicate 'subsystem == "com.notchswitch.app"'
/// ```
public enum Log {
    private static let subsystem = "com.notchswitch.app"

    /// 面板几何、展开收起、屏幕变化
    public static let panel = Logger(subsystem: subsystem, category: "panel")
    /// 悬停热区进出
    public static let hover = Logger(subsystem: subsystem, category: "hover")
    /// 层级守卫（全屏检测、系统弹窗检测、降级）
    public static let layer = Logger(subsystem: subsystem, category: "layer")
    /// 应用生命周期与辅助窗口
    public static let app = Logger(subsystem: subsystem, category: "app")
}
