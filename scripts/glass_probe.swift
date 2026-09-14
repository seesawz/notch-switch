// 探针 v3：验证「假 isKeyWindow」能否骗过 NSGlassEffectView。
//
// 已证实的结论（v2）：NSGlassEffectView 只在窗口真正是 key 时渲染液态玻璃。
// 待验证：子类覆写 `isKeyWindow` 返回 true（但不真正 makeKey）能否让玻璃点亮。
// 若能 → 修复方案零副作用（真实 key 状态不变，键盘路由不受影响）。
//
// 两个面板同屏对比：
//   A = 普通面板、非 key（对照组，应为平坦）
//   B = 覆写 isKeyWindow → true、非 key（实验组）
//   B' = 把 B 的覆写关掉（应立刻打回平坦，证明可逆）
//
// 用法: swift scripts/glass_probe.swift /tmp/glass_probe_out

import AppKit
import ScreenCaptureKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/glass_probe_out"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class ProbePanel: NSPanel {
    var fakeKey = false
    override var canBecomeKey: Bool { true }
    override var isKeyWindow: Bool { fakeKey || super.isKeyWindow }
}

let screen = NSScreen.main!
let width: CGFloat = 560, height: CGFloat = 160

func makePanel(tag: String, y: CGFloat) -> ProbePanel {
    let frame = NSRect(x: screen.frame.midX - width / 2, y: y, width: width, height: height)
    let panel = ProbePanel(contentRect: frame,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
    panel.level = .screenSaver
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.ignoresMouseEvents = true
    let glass = NSGlassEffectView()
    glass.frame = NSRect(origin: .zero, size: frame.size)
    glass.autoresizingMask = [.width, .height]
    glass.style = .clear
    glass.cornerRadius = 20
    panel.contentView?.addSubview(glass)
    panel.orderFrontRegardless()
    return panel
}

let panelA = makePanel(tag: "A", y: screen.frame.maxY - 140)          // 对照组
let panelB = makePanel(tag: "B", y: screen.frame.maxY - 340)          // 实验组

func stats(_ rep: NSBitmapImageRep) -> String {
    var sum = [Double](repeating: 0, count: 4), sum2 = sum
    var n = 0
    for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
        for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
            if let c = rep.colorAt(x: x, y: y) {
                let rgba = [Double(c.redComponent), Double(c.greenComponent),
                            Double(c.blueComponent), Double(c.alphaComponent)]
                for i in 0..<4 { sum[i] += rgba[i]; sum2[i] += rgba[i] * rgba[i] }
                n += 1
            }
        }
    }
    var out = ""
    for i in 0..<4 {
        let mean = sum[i] / Double(n)
        let sd = (sum2[i] / Double(n) - mean * mean).squareRoot()
        out += String(format: " ch%d mean=%.3f sd=%.3f;", i, mean, sd)
    }
    return out
}

@MainActor
func capture(_ panel: NSPanel, _ name: String) async {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let targetFrame = panel.frame
        if let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(panel.windowNumber) }) {
            let config = SCStreamConfiguration()
            config.width = Int(targetFrame.width) * 2
            config.height = Int(targetFrame.height) * 2
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let rep = NSBitmapImageRep(cgImage: image)
            if let data = rep.representation(using: .png, properties: [:]) {
                let url = URL(fileURLWithPath: "\(outDir)/\(name).png")
                try? data.write(to: url)
                print("[\(name)] \(url.path)\n          \(stats(rep))")
            }
        }
    } catch {
        print("[\(name)] 截图失败: \(error)")
    }
}

let done = DispatchSemaphore(value: 0)
Task { @MainActor in
    func wait(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }

    panelB.fakeKey = true                     // ← 实验变量：让 B 对外声称自己是 key
    wait(1.0)
    print("A(对照, 非key) isKeyWindow=\(panelA.isKeyWindow) B(假key) isKeyWindow=\(panelB.isKeyWindow) 但真实=\(panelB.superIsKey())")
    await capture(panelA, "A-control-not-key")
    await capture(panelB, "B-fake-key")

    panelB.fakeKey = false                     // 关掉假 key，验证可逆
    wait(1.0)
    await capture(panelB, "B2-fake-off")

    panelA.orderOut(nil)
    panelB.orderOut(nil)
    done.signal()
}
extension NSPanel {
    // 读「真实」key 状态（绕过子类覆写）：用 windowNumber 从 NSApp 查
    func superIsKey() -> Bool { NSApp.keyWindow === self }
}
while done.wait(timeout: .now() + 0.1) == .timedOut {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
