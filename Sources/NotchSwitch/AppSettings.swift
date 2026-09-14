import Combine
import Foundation
import NotchKit

/// 用户偏好（目前只有一项：无刘海屏幕是否启用顶部中央触发热区）。
///
/// 持久化在 UserDefaults；`@Published` 让菜单栏勾选态与面板控制器自动跟随，
/// 改动即时生效，不需要重启。默认开启 —— 与 v0.23 及之前「无条件启用 fallback
/// 热区」的历史行为一致（PLAN.md §4.8「或按设置不启用」）。
@MainActor
final class AppSettings: ObservableObject {

    /// 无刘海屏幕上是否仍在「屏幕顶部中央」悬停触发热区。
    /// 有刘海的屏幕不受影响；关闭只停用悬停，菜单栏的「展开 / 收起」始终可用。
    @Published private(set) var hoverWithoutNotch: Bool

    private static let hoverWithoutNotchKey = "NotchSwitch.hoverWithoutNotch"

    init() {
        // 先注册默认值再读：bool(forKey:) 对未写入过的键返回 false，不能靠它表达「默认开」
        UserDefaults.standard.register(defaults: [Self.hoverWithoutNotchKey: true])
        hoverWithoutNotch = UserDefaults.standard.bool(forKey: Self.hoverWithoutNotchKey)
    }

    /// 菜单栏开关的动作入口
    func toggleHoverWithoutNotch() {
        setHoverWithoutNotch(!hoverWithoutNotch)
    }

    private func setHoverWithoutNotch(_ value: Bool) {
        guard value != hoverWithoutNotch else { return }
        hoverWithoutNotch = value
        UserDefaults.standard.set(value, forKey: Self.hoverWithoutNotchKey)
        Log.app.notice("无刘海屏幕顶部触发 → \(value ? "开" : "关", privacy: .public)")
    }
}
