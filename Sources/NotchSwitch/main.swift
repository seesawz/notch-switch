import AppKit

// SwiftPM 的可执行 target 没有 bundle，`LSUIElement` 只在 .app 包里生效，
// 所以运行时再显式设一次激活策略，保证 `swift run` 调试时也没有 Dock 图标。
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
