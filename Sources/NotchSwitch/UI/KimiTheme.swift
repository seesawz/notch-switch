import AppKit
import NotchKit
import SwiftUI

/// 设计令牌。
///
/// 原则：界面以中性玻璃为主，品牌渐变只做小面积点缀（图标底、空态），不用于大面积填充。
///
/// ⚠️ **凡是系统设置里存在的量，一律读系统，不要在这里写死**：
/// 材质走 `GlassMaterialPolicy`（含「减弱透明度」），描边走 `Kimi.border*`（含「增强对比度」）。
enum Kimi {
    /// 品牌蓝。**这是本项目自己的品牌色**，不是从系统读的。
    /// 交互态（悬停/选中）若要跟随用户的系统强调色，应改用 `NSColor.controlAccentColor`。
    static let accent = Color(red: 0x4D / 255.0, green: 0x6B / 255.0, blue: 0xFE / 255.0)
    /// 品牌渐变的紫端
    static let accentViolet = Color(red: 0x8B / 255.0, green: 0x5C / 255.0, blue: 0xF6 / 255.0)
    /// 品牌渐变（蓝→紫），仅小面积点缀用
    static let accentGradient = LinearGradient(
        colors: [accent, accentViolet],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 描边颜色。系统开了「增强对比度」时，Apple 要求用
    /// *"a less subtle color palette or bolder lines"* —— 提高不透明度并加粗。
    static func borderColor(contrast: Bool) -> Color {
        Color.primary.opacity(contrast ? 0.42 : 0.10)
    }

    static func borderWidth(contrast: Bool) -> CGFloat {
        contrast ? 1.5 : 0.5
    }

    /// 卡片描边宽：悬停态加粗（这样即使「不依赖颜色区分」开启，悬停也不只靠颜色表达）
    static func cardBorderWidth(hovered: Bool, contrast: Bool) -> CGFloat {
        let base = borderWidth(contrast: contrast)
        return hovered ? max(base * 2, 1.5) : base
    }

    /// 调试开关只读一次（`static let` 惰性初始化），避免每次重建视图都去读 UserDefaults：
    /// ```
    /// defaults write com.notchswitch.app NotchSwitch.debugGlassFill -bool true
    /// ```
    /// 开启后材质会变成半透明红色，用于在自截图里精确看出材质区域边界。
    static let debugGlassFill = UserDefaults.standard.bool(forKey: "NotchSwitch.debugGlassFill")

    /// 玻璃上叠加的背景色不透明度（ADR-038）。
    /// 纯 `.clear` 玻璃太透，浅色背景下标题文字几乎不可读；
    /// 叠 50% 窗口背景色后约等于「50% 透明度」，同时保留折射质感。
    /// 用 `windowBackgroundColor` 而非写死白/黑：自动跟随深浅色模式。
    static let glassVeilOpacity: CGFloat = 0.5
}

extension View {
    /// 面板材质入口：**把内容嵌进玻璃容器**（内容会进入 `NSGlassEffectView.contentView`，
    /// ADR-040），不再是被包裹视图的背景。
    ///
    /// **不要换成 `.ultraThinMaterial` 或 `.glassEffect`**：那两者采样的是窗口**内部**内容，
    /// 而本面板是透明浮层、窗内是空的，换过去会立刻丢掉透视（表现为一片平坦的半透明灰）。
    ///
    /// 材质种类由 `display.resolvedGlassMaterial` 决定，**全部来自系统设置与系统版本**：
    /// - 系统开了「减弱透明度」→ 不透明背景（Apple 明确要求）
    /// - macOS 26+ → `NSGlassEffectView`（原生 Liquid Glass）
    /// - 更低版本 → `NSVisualEffectView` 窗口背后毛玻璃
    /// - Parameter cornerRadius: 玻璃自绘圆角半径（ADR-041）。仅 Liquid Glass 分支生效：
    ///   玻璃原生渲染圆角 + 连续边缘光，外层**不再 clipShape**（硬裁会切掉圆角处边缘光，
    ///   正是「背景像拼接」的来源）。回退毛玻璃（`NSVisualEffectView` 无圆角 API）仍靠
    ///   `clipShape` 裁形。
    @ViewBuilder
    func kimiGlass<Content: View>(in shape: some Shape, display: SystemDisplayOptions,
                                  cornerRadius: CGFloat = 0,
                                  @ViewBuilder content: @escaping () -> Content) -> some View {
        if Kimi.debugGlassFill {
            // 调试：用实心半透明色替代材质，用于在自截图里精确看出材质区域边界
            ZStack {
                shape.fill(Color.red.opacity(0.55))
                content()
            }
        } else {
            switch display.resolvedGlassMaterial {
            case .opaque:
                ZStack {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                    content()
                }
            case .liquidGlass, .vibrancy:
                if display.resolvedGlassMaterial == .liquidGlass {
                    GlassSurface(material: .liquidGlass, cornerRadius: cornerRadius) {
                        ZStack {
                            // ADR-038 的 50% 底色：画在「玻璃与内容之间」——
                            // 盖在玻璃折射之上，保证文字可读
                            Color(nsColor: .windowBackgroundColor).opacity(Kimi.glassVeilOpacity)
                            content()
                        }
                    }
                    // 材质切换（例如用户刚打开「减弱透明度」）时要重建视图，
                    // 否则 updateNSView 会拿到类型不匹配的旧视图
                    .id(display.resolvedGlassMaterial)
                // 不 clipShape：圆角由玻璃原生渲染（ADR-041），contentView 随玻璃统一取形
                } else {
                    GlassSurface(material: .vibrancy) {
                        ZStack {
                            Color(nsColor: .windowBackgroundColor).opacity(Kimi.glassVeilOpacity)
                            content()
                        }
                    }
                    .id(display.resolvedGlassMaterial)
                    // NSVisualEffectView 无圆角 API，只能外层硬裁（本机不可实测的回退分支）
                    .clipShape(shape)
                }
            }
        }
    }
}
