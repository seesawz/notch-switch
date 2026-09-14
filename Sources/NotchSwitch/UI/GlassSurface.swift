import AppKit
import NotchKit
import SwiftUI

/// 面板玻璃容器：**采样窗口背后内容**的玻璃，内容嵌在玻璃里（`contentView`）。
///
/// 五个约束必须同时成立，少一个就会出现「透视不对」或「玻璃消失」：
///
/// 1. **必须走 AppKit 的 behind-window 路线。**
///    SwiftUI 的 `.ultraThinMaterial` / `.glassEffect` 采样的是**窗口内部**内容，
///    而本面板是透明浮层、窗内除预览带外什么都没有 —— 它们只能折射一片空白。
///
/// 2. **`NSVisualEffectView` 回退必须显式 `state = .active`。**
///    默认 `.followsWindowActiveState` 下，Agent App 几乎永远「不活跃」
///    （面板是 `nonactivatingPanel`，点击都不会激活自己），材质会渲染成平坦的非活跃外观。
///
/// 3. **macOS 26+ 要用 Liquid Glass。**
///    `.glassEffect` 那条路满足不了第 1 条，所以改用 AppKit 的 `NSGlassEffectView`。
///
/// 4. **面板必须是 key window，玻璃才渲染（ADR-037）。**
///    实测（`scripts/glass_probe.swift`）：`NSGlassEffectView` 在窗口非 key 时
///    渲染成平坦暗色贴片。由 `NotchPanelController` 的
///    `holdKeyForLiquidGlass()` / `releaseKey()` 负责，本视图无法自行控制。
///
/// 5. **内容放进 `NSGlassEffectView.contentView`（ADR-040，Apple 官方用法）。**
///    系统把 `contentView` 当作「玻璃上的内容」与玻璃统一渲染——玻璃负责背景
///    对比度，前景可读性由系统一并调节；之前内容只是叠在玻璃上面的独立 SwiftUI
///    层，绕过了这套机制。头文件明言：只有 `contentView` 保证被放进玻璃效果内，
///    任意子视图不保证。
///
/// 6. **圆角必须由玻璃原生渲染（ADR-041）。**
///    玻璃的边缘光（rim）沿它**自己**的圆角路径画。若 `cornerRadius = 0` 再靠外层
///    `clipShape` 硬裁出异形，圆角处的边缘光会被切掉——直边有光、圆角无光，
///    背景看起来就像几块拼起来的。`NSGlassEffectView` 只支持四角统一圆角，
///    顶部两角因此从方改圆（代价见 ADR-041）。
///
/// 材质种类来自 `GlassMaterialPolicy`，样式来自 `GlassStylePolicy`，本视图不决策。
struct GlassSurface<Content: View>: NSViewRepresentable {
    var material: GlassMaterial
    /// 玻璃自绘圆角半径（四角统一，见头注释约束 6）。
    var cornerRadius: CGFloat = 0
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSView {
        let hosting = NSHostingView(rootView: content())

        if #available(macOS 26.0, *), material == .liquidGlass {
            let glass = NSGlassEffectView()
            glass.style = GlassStylePolicy.liquidStyle
            // 圆角必须原生渲染（约束 6 / ADR-041）：clipShape 硬裁会切掉圆角处的边缘光
            glass.cornerRadius = cornerRadius
            glass.contentView = hosting
            return glass
        }

        // macOS 26 以下回退：经典毛玻璃（behind-window 采样）。
        // `.popover` = 「浮在其它内容之上的浮层」，语义最贴近且比 `.hudWindow` 更透。
        // 该分支本机无法实测，属未经真机验证的选择。
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow   // ← 约束 1
        effect.state = .active                // ← 约束 2
        effect.isEmphasized = false
        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
        ])
        return effect
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if #available(macOS 26.0, *), let glass = nsView as? NSGlassEffectView {
            glass.style = GlassStylePolicy.liquidStyle
            glass.cornerRadius = cornerRadius
            (glass.contentView as? NSHostingView<Content>)?.rootView = content()
            return
        }
        if let effect = nsView as? NSVisualEffectView,
           let hosting = effect.subviews.compactMap({ $0 as? NSHostingView<Content> }).first {
            hosting.rootView = content()
        }
    }
}
