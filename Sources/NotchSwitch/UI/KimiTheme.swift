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
}

extension View {
    /// Liquid Glass 材质：macOS 26+ 用 `.glassEffect`，更低版本回退 `.ultraThinMaterial`。
    ///
    /// 全项目唯一的材质分支入口——「26 玻璃 / 低版本模糊」的差异只写在这里（ADR-023）。
    @ViewBuilder
    func kimiGlass(in shape: some Shape, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(tint.map { .regular.tint($0) } ?? .regular, in: shape)
        } else {
            background { shape.fill(.ultraThinMaterial) }
        }
    }
}
