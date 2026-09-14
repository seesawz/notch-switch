import AppKit
import NotchKit
import SwiftUI

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
/// 3. **macOS 26+ 要用 Liquid Glass。**
///    `.glassEffect` 那条路满足不了第 1 条，所以改用 AppKit 的 `NSGlassEffectView`。
///
/// 材质种类**不由这里决定** —— 它来自 `GlassMaterialPolicy`（读系统设置 + 系统版本）。
/// 本视图只负责把已经决定好的材质渲染出来。
struct GlassSurface: NSViewRepresentable {

    var material: GlassMaterial
    var tint: Color?

    func makeNSView(context: Context) -> NSView {
        switch material {
        case .liquidGlass:
            if #available(macOS 26.0, *) { return NSGlassEffectView() }
            return NSVisualEffectView()   // 理论上到不了：policy 已按版本判定
        case .vibrancy:
            return NSVisualEffectView()
        case .opaque:
            // .opaque 由 SwiftUI 侧用系统窗口背景色直接填充（见 KimiTheme.kimiGlass），
            // 不走 AppKit，避免多一层图层。
            return NSView()
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configure(nsView)
    }

    private func configure(_ nsView: NSView) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            // 取最透明的一档（`.clear`，见 GlassStylePolicy 的取舍说明）：
            // 系统那个「透明 / 着色」开关没有公开读取 API，读不到就按最透明来。
            glass.style = GlassStylePolicy.liquidStyle
            // 圆角交给 SwiftUI 的 clipShape：预览带是「上面两角方、下面两角圆」的不规则形状，
            // 而 cornerRadius 只能给统一圆角。
            glass.cornerRadius = 0
            if let tint {
                glass.tintColor = NSColor(tint)
            }
            return
        }

        guard let effect = nsView as? NSVisualEffectView else { return }
        // `.popover` = 「浮在其它内容之上的浮层」，是与本面板语义最接近、且比 `.hudWindow` 更透的材质。
        // 注意：这条回退分支只在 macOS 26 以下生效，本机（26/27）走的是 Liquid Glass，
        // **该材质在本机无法实测**，属未经真机验证的选择。
        effect.material = .popover
        effect.blendingMode = .behindWindow   // ← 约束 1
        effect.state = .active                // ← 约束 2
        effect.isEmphasized = false
    }
}
