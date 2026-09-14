import Foundation

/// 面板背景最终采用的材质。
///
/// 完全由「系统设置 + 系统版本」推导，**不含任何我们自己编的数值**
/// —— 之前硬编码 `style = .regular` 就是错的。
public enum GlassMaterial: String, Equatable {
    /// 不透明背景。系统开了「减弱透明度」时必须走这条，
    /// 因为 Apple 明确要求此类 UI 的背景「should be opaque」。
    case opaque
    /// macOS 26+ 的原生 Liquid Glass（`NSGlassEffectView`）
    case liquidGlass
    /// `NSVisualEffectView` 的窗口背后毛玻璃（macOS 26 以下）
    case vibrancy
}

/// 材质决策。抽成纯函数以便单测 —— 这类「必须跟着系统走」的规则最怕被后人随手改坏。
public enum GlassMaterialPolicy {

    /// 调试用的强制回退开关（默认不设 = 跟随系统）：
    /// ```
    /// defaults write com.notchswitch.app NotchSwitch.forceVibrancy -bool true
    /// ```
    public static var hasBlurOverride: Bool {
        UserDefaults.standard.bool(forKey: "NotchSwitch.forceVibrancy")
    }

    /// 当前系统是否支持 Liquid Glass
    public static var isLiquidGlassAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }

    /// 决策顺序有意义：
    /// 1. **减弱透明度优先于一切** —— 这是无障碍要求，用户开它就是因为玻璃让他看不清，
    ///    此时还给他一块玻璃等于直接违背意图
    /// 2. 调试开关次之
    /// 3. 最后才按系统版本选原生材质
    public static func resolve(
        reduceTransparency: Bool,
        supportsLiquidGlass: Bool,
        blurOverride: Bool
    ) -> GlassMaterial {
        if reduceTransparency { return .opaque }
        if blurOverride { return .vibrancy }
        return supportsLiquidGlass ? .liquidGlass : .vibrancy
    }
}
