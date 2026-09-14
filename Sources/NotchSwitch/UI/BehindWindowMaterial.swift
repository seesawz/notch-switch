import AppKit
import SwiftUI

/// 采样**窗口背后**内容的毛玻璃背景。
///
/// 为什么不能用 SwiftUI 的 `.ultraThinMaterial` / `.glassEffect`：
///
/// 1. **`.glassEffect` 采样的是窗口内部的内容**（它是应用内材质），
///    而我们的面板是一个透明浮层，窗内除了一条预览带什么都没有——
///    于是它只能折射一片空白，看起来「没有透视」。
///    要让浮层透出桌面/菜单栏，必须用 `NSVisualEffectView` 的 `.behindWindow` 混合模式。
///
/// 2. **`state` 默认值是 `.followsWindowActiveState`**：
///    App 不活跃时材质会渲染成「非活跃」的平坦外观。
///    而 NotchSwitch 是 Agent App，被点击时也不激活自己（`nonactivatingPanel`），
///    所以**几乎永远处于「不活跃」**——玻璃会一直是死的。必须显式设 `.active`。
struct BehindWindowMaterial: NSViewRepresentable {

    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    /// ⚠️ 必须是 `.active`，理由见上
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = false
    }
}
