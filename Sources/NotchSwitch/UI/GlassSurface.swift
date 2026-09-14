import AppKit
import SwiftUI

/// 面板背景材质的候选实现。
///
/// 两档存在的意义：视觉这种事没法靠推断，留个开关让用户一键 A/B，
/// 而不是每次都要改代码重编。
///   - `liquid`：`NSGlassEffectView`（macOS 26+ 的原生 Liquid Glass），低版本自动回退
///   - `blur`：`NSVisualEffectView` 经典毛玻璃
enum GlassMaterialKind: String {
    case liquid
    case blur

    /// 切换方式（改完需要重启 App，视图类型在创建时就定了）：
    /// ```
    /// defaults write com.notchswitch.app glassMaterial blur   # 换成经典毛玻璃
    /// defaults delete com.notchswitch.app glassMaterial       # 换回 Liquid Glass
    /// ```
    static var preferred: GlassMaterialKind {
        guard let raw = UserDefaults.standard.string(forKey: "NotchSwitch.glassMaterial"),
              let kind = GlassMaterialKind(rawValue: raw) else { return .liquid }
        return kind
    }
}

/// 面板背景：**采样窗口背后内容**的玻璃。
///
/// 三个约束必须同时成立，少一个就会出现「透视不对」或「玻璃消失」：
///
/// 1. **必须走 AppKit 的 behind-window 路线。**
///    SwiftUI 的 `.ultraThinMaterial` / `.glassEffect` 采样的是**窗口内部**内容，
///    而本面板是透明浮层、窗内除预览带外什么都没有 —— 它们只能折射一片空白。
///
/// 2. **`NSVisualEffectView` 必须显式 `state = .active`。**
///    默认 `.followsWindowActiveState` 下，Agent App 几乎永远「不活跃」
///    （面板是 `nonactivatingPanel`，点击都不会激活自己），材质会渲染成平坦的非活跃外观。
///
/// 3. **macOS 26+ 要用 Liquid Glass，不能只有经典毛玻璃。**
///    `.glassEffect` 那条路满足不了第 1 条，所以改用 AppKit 的 `NSGlassEffectView`
///    —— 它既是原生 Liquid Glass，又按 behind-window 方式采样。
struct GlassSurface: NSViewRepresentable {

    var tint: Color?

    func makeNSView(context: Context) -> NSView {
        if #available(macOS 26.0, *), GlassMaterialKind.preferred == .liquid {
            return NSGlassEffectView()
        }
        return NSVisualEffectView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ nsView: NSView) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.style = .regular
            // 圆角一律交给 SwiftUI 的 clipShape —— 预览带是「上面两角方、下面两角圆」的
            // 不规则形状，而 cornerRadius 只能给统一圆角。
            glass.cornerRadius = 0
            if let tint {
                glass.tintColor = NSColor(tint)
            }
            return
        }

        guard let effect = nsView as? NSVisualEffectView else { return }
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow   // ← 约束 1
        effect.state = .active                // ← 约束 2
        effect.isEmphasized = false
    }
}
