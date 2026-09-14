import AppKit
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

/// Liquid Glass 的 `style` 选择。
///
/// **背景**：系统设置里 Liquid Glass 的「透明 / 着色」开关**没有公开读取 API**
/// （`NSGlassEffectView.h` 只有 `style` / `cornerRadius` / `tintColor` / `contentView` 四个成员，
/// 没有任何表示用户偏好的属性）。读不到就由我们定，现行值见下方「演变」。
///
/// 依据（头文件原文）：
/// ```
/// /// Standard glass effect style.
/// NSGlassEffectViewStyleRegular,
/// /// Clear glass effect style.
/// NSGlassEffectViewStyleClear
/// ```
/// `.regular`（标准档，现行）/ `.clear`（最透明档）。
///
/// **演变**：v0.23（ADR-035）取最透明的 `.clear`；后续实测浅色背景下可读性不行
/// （ADR-035 预留的信号触发），先叠 50% 底色（ADR-038），再按用户要求换更浓的
/// `.regular`（ADR-039）——系统菜单栏那种玻璃感。若觉得太厚，调 `Kimi.glassVeilOpacity`（可降为 0）。
/// 代价（必须知情）：玻璃越透明，直接压在面板上的文字越难读。
/// 我们面板里的主要内容是**缩略图**（本身不透明，不受影响）与单行标题。
///
/// **后续（ADR-038/039）**：可读性信号实测触发。现行为 `.regular` + 玻璃上叠
/// 50% 窗口背景色（`Kimi.glassVeilOpacity`）；若嫌太实可降 veil 或回 `.clear`。
@available(macOS 26.0, *)
public enum GlassStylePolicy {
    public static let liquidStyle: NSGlassEffectView.Style = .regular

    public static var debugDescription: String {
        switch liquidStyle {
        case .clear: "Liquid Glass style = .clear（最透明）"
        case .regular: "Liquid Glass style = .regular（标准，现行）"
        @unknown default: "Liquid Glass style = 未知(\(liquidStyle.rawValue))"
        }
    }
}
