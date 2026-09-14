import AppKit
import SwiftUI

/// Kimi 风格设计令牌。
///
/// 原则：界面以中性玻璃/毛玻璃为主，品牌渐变只做小面积点缀
/// （图标底、悬停描边、空态），不用于大面积填充。
enum Kimi {
    /// Kimi 品牌蓝
    static let accent = Color(red: 0x4D / 255.0, green: 0x6B / 255.0, blue: 0xFE / 255.0)
    /// 品牌渐变的紫端
    static let accentViolet = Color(red: 0x8B / 255.0, green: 0x5C / 255.0, blue: 0xF6 / 255.0)
    /// 品牌渐变（蓝→紫），仅小面积点缀用
    static let accentGradient = LinearGradient(
        colors: [accent, accentViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 调试开关只读一次（`static let` 惰性初始化），避免每次重建视图都去读 UserDefaults：
    /// ```
    /// defaults write com.notchswitch.app NotchSwitch.debugGlassFill -bool true
    /// ```
    /// 开启后材质会变成半透明红色，用于在自截图里精确看出材质区域边界。
    static let debugGlassFill = UserDefaults.standard.bool(forKey: "NotchSwitch.debugGlassFill")
}

extension View {
    /// 面板材质入口（ADR-029 / ADR-032）。
    ///
    /// **不要换成 `.ultraThinMaterial` 或 `.glassEffect`**：那两者采样的是窗口**内部**内容，
    /// 而本面板是透明浮层、窗内是空的，换过去会立刻丢掉透视（表现为一片平坦的半透明灰）。
    /// Liquid Glass 的观感由 AppKit 的 `NSGlassEffectView` 提供，细节见 `GlassSurface`。
    ///
    /// 想对比经典毛玻璃：
    /// ```
    /// defaults write com.notchswitch.app NotchSwitch.glassMaterial blur   # 重启 App 生效
    /// ```
    @ViewBuilder
    func kimiGlass(in shape: some Shape, tint: Color? = nil) -> some View {
        background {
            if Kimi.debugGlassFill {
                // 调试：用实心半透明色替代材质，用于在自截图里精确看出材质区域边界
                shape.fill(Color.red.opacity(0.55))
            } else {
                GlassSurface(tint: tint)
                    .clipShape(shape)
            }
        }
    }
}
