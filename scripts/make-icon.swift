// 生成 App 图标：scripts/make-icon.swift > 产出 Resources/AppIcon.icns
//
// 用法：swift scripts/make-icon.swift
// 依赖：macOS 自带 swift + iconutil，无第三方库。
//
// 设计：macOS 圆角方形底（深色玻璃渐变）+ 顶部刘海剪影 + 三张窗口预览卡，
// 中间卡片用品牌蓝描边（Kimi.accent #4D6BFE）——即「悬停中的那张卡」。
// 所有元素按 1024 画布参数化绘制，每个尺寸独立重画（不做位图缩放），小尺寸不发糊。

import AppKit

let accent = NSColor(red: 0x4D / 255.0, green: 0x6B / 255.0, blue: 0xFE / 255.0, alpha: 1)

func drawIcon(size: CGFloat) {
    // 以下坐标全部按 1024 画布描述，s 为缩放系数
    let s = size / 1024
    func r(_ v: CGFloat) -> CGFloat { v * s }

    // 底板：macOS 风格圆角方形，四周留出阴影余量
    let board = NSRect(x: r(100), y: r(100), width: r(824), height: r(824))
    let boardPath = NSBezierPath(roundedRect: board, xRadius: r(186), yRadius: r(186))

    // 底板投影（很轻，只为了从纯白背景里托起来）
    NSShadow().set()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = r(26)
    shadow.shadowOffset = NSSize(width: 0, height: r(-14))
    NSGraphicsContext.current?.saveGraphicsState()
    shadow.set()
    boardPath.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    // 底板填充：深色纵向渐变（上亮下暗，模拟玻璃受光）
    let gradient = NSGradient(
        starting: NSColor(red: 0x2B / 255.0, green: 0x2B / 255.0, blue: 0x3A / 255.0, alpha: 1),
        ending: NSColor(red: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x1C / 255.0, alpha: 1)
    )!
    gradient.draw(in: boardPath, angle: -90)

    // 底板边缘微光：一圈很淡的内描边，卖「玻璃边缘」的感觉
    NSColor.white.withAlphaComponent(0.10).setStroke()
    boardPath.lineWidth = r(3)
    boardPath.stroke()

    // 刘海剪影：贴着底板上缘的黑色圆角矩形（上缘与底板平齐）
    let notchWidth = r(320)
    let notchHeight = r(58)
    let notchX = size / 2 - notchWidth / 2
    let notchTop = board.maxY
    let notch = NSBezierPath(roundedRect: NSRect(x: notchX, y: notchTop - notchHeight,
                                                 width: notchWidth, height: notchHeight),
                             xRadius: r(20), yRadius: r(20))
    NSColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 1).setFill()
    notch.fill()
    // 刘海下缘一条高光线
    NSColor.white.withAlphaComponent(0.14).setStroke()
    let rim = NSBezierPath()
    rim.move(to: NSPoint(x: notchX + r(22), y: notchTop - notchHeight))
    rim.line(to: NSPoint(x: notchX + notchWidth - r(22), y: notchTop - notchHeight))
    rim.lineWidth = r(3)
    rim.stroke()

    // 预览带：三张窗口卡片，中间一张是「悬停高亮」
    let cardWidth = r(216)
    let cardHeight = r(166)
    let cardGap = r(36)
    let cardY = r(470)
    let totalWidth = cardWidth * 3 + cardGap * 2
    var cardX = size / 2 - totalWidth / 2

    for index in 0..<3 {
        let hovered = index == 1
        let card = NSBezierPath(roundedRect: NSRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight),
                                xRadius: r(26), yRadius: r(26))

        if hovered {
            // 品牌蓝描边 + 同色柔光（对应产品里悬停卡片的 accent 描边）
            NSGraphicsContext.current?.saveGraphicsState()
            let glow = NSShadow()
            glow.shadowColor = accent.withAlphaComponent(0.65)
            glow.shadowBlurRadius = r(22)
            glow.shadowOffset = NSSize(width: 0, height: 0)
            glow.set()
            NSColor.white.withAlphaComponent(0.16).setFill()
            card.fill()
            NSGraphicsContext.current?.restoreGraphicsState()
            accent.setStroke()
            card.lineWidth = r(8)
        } else {
            NSColor.white.withAlphaComponent(0.10).setFill()
            card.fill()
            NSColor.white.withAlphaComponent(0.28).setStroke()
            card.lineWidth = r(3.5)
        }
        card.stroke()

        // 卡片内的「窗口内容」示意：标题条 + 内容块
        let contentColor = NSColor.white.withAlphaComponent(hovered ? 0.30 : 0.20)
        let title = NSBezierPath(roundedRect: NSRect(x: cardX + r(24), y: cardY + cardHeight - r(44),
                                                     width: cardWidth * 0.55, height: r(14)),
                                 xRadius: r(7), yRadius: r(7))
        contentColor.setFill()
        title.fill()
        let body = NSBezierPath(roundedRect: NSRect(x: cardX + r(24), y: cardY + r(22),
                                                    width: cardWidth - r(48), height: r(58)),
                                xRadius: r(10), yRadius: r(10))
        NSColor.white.withAlphaComponent(hovered ? 0.14 : 0.09).setFill()
        body.fill()

        cardX += cardWidth + cardGap
    }
}

func renderPNG(pixelSize: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixelSize, pixelsHigh: pixelSize,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(size: CGFloat(pixelSize))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// macOS iconset 所需的全部尺寸（含 @2x）
let sizes = [16, 32, 64, 128, 256, 512, 1024]

let arguments = CommandLine.arguments
let outputDir = arguments.count > 1 ? arguments[1] : "AppIcon.iconset"

let fileManager = FileManager.default
try? fileManager.removeItem(atPath: outputDir)
try! fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

for pixelSize in sizes {
    let data = renderPNG(pixelSize: pixelSize)
    // 一半尺寸作为它的 @1x（1024 除外）
    if pixelSize >= 32 {
        let baseName = "icon_\(pixelSize / 2)x\(pixelSize / 2)@2x.png"
        try! data.write(to: URL(fileURLWithPath: "\(outputDir)/\(baseName)"))
    }
    if pixelSize <= 512 {
        let name = "icon_\(pixelSize)x\(pixelSize).png"
        try! data.write(to: URL(fileURLWithPath: "\(outputDir)/\(name)"))
    }
}

print("iconset 已生成：\(outputDir)/")
print("下一步：iconutil -c icns \(outputDir) -o AppIcon.icns")
