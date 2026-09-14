# NotchSwitch — 刘海窗口切换器 · 项目计划文档

> 本文档是项目的**唯一权威计划与决策记录（living document）**，随开发进展持续更新。
> 每次有结论变化、技术选型调整或里程碑推进，请同步更新「更新日志」+「决策记录」两节。

| 项 | 值 |
|---|---|
| 文档版本 | v0.11（取消滚动吸附） |
| 最后更新 | 2026-09-14 |
| 当前阶段 | M0~M3 已完成 · M4 部分完成（滚动已做，搜索待做） |
| 目标平台 | macOS 14+（Apple Silicon 优先，Intel 尽力兼容） |
| 开发环境（本机实测） | macOS 27.0 (26A428) / Xcode 26.3 / Swift 6.2.4 |
| 一句话定位 | 把 MacBook 的刘海变成「前台调度」式的横向窗口切换条：小预览常驻刘海，hover 出大预览，点击即切 |

---

## 更新日志

| 日期 | 版本 | 变更 |
|---|---|---|
| 2026-09-14 | v0.1 | 完成竞品/技术调研，落地本文档；确认本机刘海几何数据；确定自研 + NSPanel 贴片路线 |
| 2026-09-14 | v0.2 | 交互规格更新：① 可视区固定 4 张卡片，改为 Shift + 滚轮逐张滚动（放弃 2 行网格）；② 明确「常驻最前台」层级策略与唯一例外（其他 App 全屏）。新增 §4.1.1、§6.5、§6.6，ADR-008~010，风险 R13~R16，开放问题 Q7~Q8 |
| 2026-09-14 | v0.3 | M0 完成、M1 代码落地：NotchKit 8 个模块 + 应用外壳 6 个文件 + 7 项几何单测全部通过；`swift build` / `swift test` / `.app` 冒烟测试通过。新增 ADR-011~013、§13 验收记录；§5.1 模块表改为实际文件结构 |
| 2026-09-14 | v0.4 | 加入 `os.Logger` 日志系统（`Log.swift`）与调试手册（§14）。**日志上线后立刻抓到并修复一个严重 bug**：`isFloatingPanel = true` 会静默覆盖 `level = .screenSaver`，导致面板层级掉到 3（浮动），被菜单栏压住。新增 ADR-014 |
| 2026-09-14 | v0.5 | **修复「授权失败后再无入口」**：删掉「只提示一次」的持久化标记，改为权限未齐时每次启动都自动打开引导窗口；引导窗口加入运行位置警告、重启按钮；菜单栏在未授权时显示警告图标。新增 `scripts/reset-permissions.sh`、`scripts/run-app.sh`。新增 ADR-015 与 §14.7 授权排查手册 |
| 2026-09-14 | v0.6 | **打通签名链路**（原脚本从第一版起就是坏的，实测失败才发现）：① OpenSSL 3.x 导出的 p12 macOS 不认 → 改为直接导入 PEM；② 缺 `set-key-partition-list` 导致 codesign 报 `errSecInternalComponent`；③ `find-identity -v` 会过滤掉自签名身份 → 去掉 `-v`；④ 不需要 `add-trusted-cert`，省掉 GUI 密码框；⑤ 同一 bundle id 存在两份时 LaunchServices 会解析到旧路径 → `--install` 后删除 build 副本。签名改为独立钥匙串方案。新增 ADR-017~019、§14.8 |
| 2026-09-14 | v0.7 | **M2 + M3 落地**：窗口枚举（AX + `_AXUIElementGetWindow`）、MRU 事件驱动排序、三级窗口激活、ScreenCaptureKit 缩略图与 LRU 缓存、真实窗口卡片替换占位内容、Shift+滚轮翻卡。单测 24 项全绿。实测枚举到 9 窗口/6 应用。**Q1 得到确认：私有 `_AXUIElementGetWindow` 在 macOS 27 上仍可用。** 修正文档中无效的 `log --level debug` 参数（正确为 `--debug`）。新增 ADR-020 |
| 2026-09-14 | v0.8 | 面板精简：移除底部状态栏（诊断文本 / `3/9` 计数 / Shift 提示）与应用筛选条，面板只展示窗口卡片。展开高 198 → **148**。**副作用：R17 升级为高风险**——窗口多于 4 个时面板内再无任何提示，替代方案待定 |
| 2026-09-14 | v0.9 | **修复「滚动不够丝滑」**。根因不是参数没调好，而是渲染方式：原来按索引换一批卡片，视觉上必然是瞬移。改为「所有卡片排成一长条 + 连续像素位移 + 帧同步指数跟随 + 松手吸附」。触控板 1:1 跟手、机械滚轮 ×0.55；平滑用**时间常数** τ=0.035s 而非每帧固定比例，保证 60/120Hz 手感一致。删除 `ScrollStepAccumulator`，新增 `ScrollDelta` + `ScrollFollow`，单测 29 项。新增 ADR-021 |
| 2026-09-14 | v0.10 | 滚动**去掉 Shift 前置条件**：直接滚轮 / 双指滑动即可翻卡。轴向改用「主导轴」判定（取绝对值大的轴），兼容普通滚轮、双指左右滑、Shift 转轴三种输入。**同时修掉一个会让滚轮「几乎没反应」的 bug**：机械滚轮的 `scrollingDelta` 是**行数**不是点，原先 ×0.55 导致一格只走 0.55pt，改为按行高 44pt 换算并封顶 ±120pt。无溢出时不消费滚动事件。单测 31 项。新增 ADR-022 |
| 2026-09-14 | v0.11 | **取消松手吸附**：滚到哪里就停在哪里，允许停在半张卡中间。`ScrollFollow.snap` 与 `PanelSelection.settleDelay` 已删除，相关单测替换为「停位不被拉回边界」的断言。新增 ADR-023 |
| 2026-09-14 | v0.11 | **UI 全面改版为 Kimi 风格 + Liquid Glass**：预览带材质改用 `.glassEffect`（macOS 26+，低版本回退 `.ultraThinMaterial`，入口统一在 `UI/KimiTheme.swift`）；卡片新增悬停反馈（微放大 + 品牌色描边 + 投影）；图标降级为毛玻璃小圆片；空态改渐变圆徽；权限引导窗口改卡片式布局 + 状态胶囊 + 品牌渐变按钮。**几何与交互参数零改动**，不影响滚动手感。新增 ADR-023 |
| 2026-09-14 | v0.12 | **修两个实测 bug**：① **访达多出一张卡片**——AX 会给访达多报一个全屏桌面元素（`subrole=nil`），原过滤只挡「有 subrole 但不是 StandardWindow」，`nil` 漏过；改为严格 `== AXStandardWindow`（实测 9 → 8 窗口）。② **滚动方向不跟随系统设置**——NSEvent 约定「+ = 回退」，预览带需要「下滚/左滑 = 前进」，`ScrollDelta.stripOffset` 统一取反，系统已按「自然滚动」翻过符号，取反即自动跟随。单测 32 项。新增 ADR-024~025 |

---

## 1. 产品定义

### 1.1 一句话描述

在 MacBook 刘海正下方贴一条**横向的窗口小预览带**，鼠标悬停时展开为**大预览图 + 实时缩略图**，点击/回车即把目标窗口切到前台。相当于把 macOS「前台调度（Stage Manager）」的窗口条搬到刘海，并且**不需要先打开 App** 就能看到所有窗口的画面。

### 1.2 核心交互流

```
[收起态] 刘海即热区（视觉无侵入，仅 185×32pt 透明热区）
        面板常驻最前台，不被任何 App 窗口遮挡，唯一例外：其他 App 全屏
    │ 鼠标进入刘海带
    ▼
[展开态 A · 小预览带] 刘海向下"长出"一条横向卡片条
    · 可视区固定 4 张卡片（单行、不换行）
    · 每张卡 = 窗口实时缩略图（16:10 裁切）+ 应用图标 + 标题（单行省略）
    · 按最近使用（MRU）从中间向两侧排布
    · 卡片多于 4 张时：按住 Shift + 滚轮，向前/向后逐张滚动（见 §6.5）
    · 底部一行应用筛选条（点图标只看该应用的窗口）
    │ 悬停某张卡 250~300ms
    ▼
[展开态 B · 大预览] 该卡下方弹出大预览浮层
    · 原始宽高比缩放，最大 640×400pt
    · 标题 / 应用名 / 所在屏幕 / 最小化标记 / ✕ 关闭按钮
    · 可键盘 ←→ 切换卡片，大预览跟随
    │ 点击卡片 / 回车
    ▼
[切换] 目标窗口提升到前台并聚焦（含跨 App、跨 Space 处理）
```

### 1.3 必须支持（v1）

| 编号 | 能力 | 说明 |
|---|---|---|
| F1 | 刘海热区 | 有刘海机型：热区 = 刘海矩形；无刘海机型/外接屏：热区 = 菜单栏中央一段（可配置） |
| F2 | 悬停展开/自动收起 | 进入展开，移出 200~400ms 后收起 |
| F3 | 横向小预览带 | 单行横向卡片条，**可视区固定 4 张**，不换行，卡片可点击 |
| F4 | 大预览 | 悬停卡片后延迟弹出大图，跟随键盘选择 |
| F5 | MRU 排序 | 真实「最近使用」顺序，而非启动顺序 |
| F6 | 窗口切换 | 点击即切；跨 Space / 全屏 / 最小化窗口有明确策略 |
| F7 | 应用筛选条 | 底部应用图标条，过滤单应用窗口 |
| F8 | 键盘操作 | 展开后直接键入搜索；←→ 选择；Return 打开；Esc 逐级关闭 |
| F9 | 权限引导 | 无障碍 + 屏幕录制缺失时给出可操作的引导与降级 |
| F10 | 多显示器 | 只贴在带刘海的内建屏；外接屏不显示或按设置显示 |
| F11 | 常驻最前台 | 面板层级压制所有普通 App 窗口、系统通知与菜单栏；**唯一例外：其他 App 进入全屏时被遮挡并自动收起** |
| F12 | Shift + 滚轮翻卡 | 卡片 > 4 张时，按住 Shift 滚轮向前/向后逐张滚动可视区（见 §6.5） |

### 1.4 明确不做（v1 non-goals）

- 不做窗口平铺 / 分屏（Tiling），不做 Mission Control 替代品
- 不做音乐播放器、文件暂存架等「动态岛」功能（那是 Boring Notch / NotchNook 的赛道）
- 不做 Dock 替换
- 不支持 Intel + 无刘海的老机型作为一等目标（尽力兼容，不作承诺）
- 不追求 Mac App Store 上架（见 §4.11 分发决策）
- 不做 2 行网格布局（改用「固定 4 张 + Shift 滚轮翻卡」，见 ADR-009）

---

## 2. 竞品调研结论

### 2.1 刘海应用生态（做「刘海入口」的）

| 产品 | 形态 | 许可 | 借鉴价值 |
|---|---|---|---|
| Boring Notch | 音乐/文件架/日历全家桶 | GPL-3.0 | **不可抄代码**，可参考交互壳 |
| NotchNook | 动态岛式刘海，商业 | 商业 | 商业形态参考 |
| NotchDrop / Notchy / NotchNest | 刘海工具集 | 多为开源/商业混 | 视觉与材质处理 |
| DynamicNotchKit | 刘海窗口库（不提供功能） | **MIT** | **可直接复用**：刘海几何 + panel 配置 |
| NotchVeil | 刘海遮盖 | 开源 | 边界场景参考 |

### 2.2 窗口切换器（做「窗口预览」的）

| 产品 | 说明 | 许可 |
|---|---|---|
| alt-tab-macos | 最完整的开源 Alt-Tab，27k 行 /162 文件 | GPL-3.0，**只能读架构思路** |
| AltTab（kaikozlov 版，约 1500 行） | 极简实现，含完整架构文档 | 参考价值极高（思路层） |
| DockDoor | Dock 悬停预览 + Alt-Tab | GPL-3.0 |
| **louislili/MacDock** | **「刘海屏 Mac 轻量窗口切换器」——与本项目定位几乎重合** | MIT |
| Contexts / Hyperswitch 等 | 商业 Alt-Tab 增强 | 商业 |

### 2.3 最重要的竞品发现：MacDock

`louislili/MacDock`（MIT，极早期：10 commits / 0 stars）功能是：刘海悬停展开 + 实时缩略图 + MRU 排序 + 两排网格 + 底部应用条 + 拼音搜索。

**结论**：产品想法并不独特，但该竞品处于极早期（无测试、无公证包、仍在用已弃用的 `CGWindowListCreateImage`、仅限 macOS 14+ Apple Silicon）。我们的差异化必须建立在：

1. **大预览（F4）**——竞品是网格卡片，没有 hover 大图预览，这是我们的主打
2. **视觉与 Liquid Glass 融合**——macOS 26/27 液态玻璃菜单栏下的观感是核心体验门槛
3. **跨 Space / 全屏 / 最小化窗口的正确切换**——竞品未证明处理好了这块，这是最难的 20%
4. **稳定性与包体分发**——公证包 + Sparkle 更新 + 自动化测试

### 2.4 许可红线（重要）

以下仓库是 **GPL-3.0**：`boring.notch`、`DockDoor`、`alt-tab-macos`。**只能阅读其架构思想，禁止复制代码片段**，否则本项目将被传染为 GPL。
可安全复用（MIT）：`DynamicNotchKit`（刘海几何算法）、`MacDock`（思路层，仍需谨慎）。

自研优先；确需引入库时只允许 MIT / Apache-2.0。

---

## 3. 本机环境实测数据（2026-09-14）

用 `NSScreen` API 实测当前机器，用于确定默认几何参数（**注意：运行时必须动态计算，不得硬编码**）：

```
内建屏 Built-in Retina Display
  frame              = (0, 0, 1728, 1117)       // 缩放后点数，物理 3456×2234 @2x
  visibleFrame       = (0, 0, 1728, 1084)
  safeAreaInsets.top = 32                         // ← 刘海高度 (pt)
  auxiliaryTopLeftArea  = (0, 1085, 771.5, 32)
  auxiliaryTopRightArea = (956.5, 1085, 771.5, 32)
  → 刘海宽度 = 1728 − 771.5 − 771.5 = 185        // ← 刘海宽度 (pt)
  → 刘海矩形 = (771.5, 1085, 185, 32)
  → 菜单栏高 = frame.maxY − visibleFrame.maxY = 33

外接屏 Redmi 27 NQ
  safeAreaInsets.top = 0, auxiliaryTopLeftArea = nil, auxiliaryTopRightArea = nil
  → 无刘海，必须走 fallback 分支
```

**关键判断**：`auxiliaryTopLeftArea == nil` 是「该屏无刘海」的可靠判据（macOS 12+）。`NSScreen.main` 是「当前 key window 所在屏」，**不能用来找刘海屏**，必须遍历 `NSScreen.screens` 挑 `notchFrame != nil` 的那块。

### 刘海几何算法（参考 DynamicNotchKit，MIT）

```swift
extension NSScreen {
    var notchFrame: NSRect? {
        guard let l = auxiliaryTopLeftArea?.width,
              let r = auxiliaryTopRightArea?.width else { return nil }   // nil = 无刘海
        let w = frame.width - l - r
        return NSRect(x: frame.midX - w / 2,
                      y: frame.maxY - safeAreaInsets.top,
                      width: w,
                      height: safeAreaInsets.top)
    }

    var menubarHeight: CGFloat { frame.maxY - visibleFrame.maxY }
}
```

---

## 4. 技术可行性分析

### 4.1 刘海贴片（核心可行性 — 已验证成熟路线）

本质：一个透明、无边框、层级足够高的 `NSPanel` 贴在刘海位置，内容用 SwiftUI 画。所有刘海应用（含上面所有竞品）都是这一招。

| 配置项 | 取值 | 原因 |
|---|---|---|
| `level` | `.screenSaver`（=1000） | **必须够高**：既压过菜单栏(24)、状态栏(25)、弹出菜单(101)，也压过所有普通 App 窗口(0) → 这是「常驻最前台」的基础 |
| `styleMask` | `[.borderless, .nonactivatingPanel]` | 无边框；点击不抢焦点、不打断前台 App |
| `collectionBehavior` | `[.canJoinAllSpaces, .stationary]`，**故意不加 `.fullScreenAuxiliary`** | 跨 Space 常驻；不加 `fullScreenAuxiliary` 才能让「其他 App 全屏」遮挡我们（符合需求） |
| `hidesOnDeactivate` | **必须显式设为 `false`** | `NSPanel` 默认为 `true`，而 Agent App 会频繁失活 → 不设就「一激活别的 App 面板就消失」（**最容易踩的坑**） |
| `isFloatingPanel` | `true` | 明确浮游面板语义 |
| `worksWhenModal` | `true` | 别的 App 弹模态框时仍不消失 |
| `hasShadow` | `false` | 贴边无阴影才自然 |
| `backgroundColor` | `.clear` | 透明 |
| `override var canBecomeKey` | 展开态 `true` / 收起态 `false` | 需要接键盘搜索与滚轮时必须能成为 key |
| 显示 | `orderFrontRegardless()` | 不激活 App 也能显示（不依赖 `makeKeyAndOrderFront`） |
| `NSHostingView` | 必须手动撑满 panel 并设 `autoresizingMask` | 否则 SwiftUI `maxHeight: .infinity` / 对齐全失效 |

**结论：技术完全可行，风险低。** 反向圆角（刘海与面板接缝处）需要自绘 `Path`，属打磨项。

#### 4.1.1 常驻最前台策略（F11）

目标：面板**始终位于所有 App 窗口之上**；唯一例外是「其他 App 进入全屏」。

实现组合（缺一不可）：

1. `level = .screenSaver`（1000）——高于普通窗口(0)、浮动(3)、模态面板(8)、菜单栏(24)、状态栏(25)、弹出菜单(101)
2. `hidesOnDeactivate = false` + `isFloatingPanel = true`——Agent App 频繁失活，这两项是「不消失」的前提
3. `orderFrontRegardless()`——需要时重新置前，且不激活本 App
4. **不添加 `.fullScreenAuxiliary`**——这是「允许窗口出现在全屏 Space 之上」的开关，不加即可让全屏 App 遮挡我们
5. **Space 变化兜底**：监听 `NSWorkspace.shared.notificationCenter` 的 `activeSpaceDidChangeNotification`，判断当前 Space 是否为「全屏 Space」；是则 `orderOut()` 面板并暂停 hover 展开，退出全屏后 `orderFrontRegardless()` 恢复
   - Space 类型判断优先级：私有 `CGSSpaceGetType` → `NSWindow` 全屏标志探测 → 启发式兜底（AX 最前窗口尺寸 == 屏幕尺寸）
6. **反向保护（必须做）**：我们自己的设置窗口、系统权限授权对话框**不能被自己遮挡**，否则用户无法完成授权、流程卡死 → 检测到自身弹窗或系统模态时，临时把 level 降到 `.floating`，并强制收起面板

**待实测**：`canJoinAllSpaces` 的窗口在「全屏 Space」中的实际表现是否真的被遮挡（见 Q7）。若不遮挡，则第 5 条的主动收起就是主要实现手段。

### 4.2 窗口枚举

| 数据源 | 能拿到 | 权限 |
|---|---|---|
| `NSWorkspace.shared.runningApplications` | 运行中的应用、bundleId、图标、activationPolicy | 无 |
| `CGWindowListCopyWindowInfo` | CGWindowID、owner PID、bounds、layer、alpha | 无权限可拿几何；`kCGWindowName`（标题）**需要屏幕录制权限** |
| `AXUIElement` + `kAXWindowsAttribute` | 窗口对象、标题、minimized、position/size、可操作性 | **需要无障碍权限** |
| `_AXUIElementGetWindow`（私有，但长期稳定） | AXUIElement → CGWindowID 的映射 | 需要无障碍权限 |

策略：**AX 为主，CG 为辅**。AX 拿到可操作窗口列表与标题；CG 负责几何/层级过滤（排除菜单栏、悬浮层、阴影窗口）。过滤规则：`kCGWindowLayer == 0`、`alpha > 0`、尺寸 > 阈值、排除自己。

### 4.3 MRU（最近使用顺序）— 最大的「没有公开 API」问题

macOS **不提供**任何窗口级（甚至应用级）最近使用顺序的公开 API。只能自建：

- 对每个 `.regular` activationPolicy 的应用创建 `AXObserver`
- 订阅：`kAXWindowCreatedNotification`、`kAXUIElementDestroyedNotification`、`kAXFocusedWindowChangedNotification`、`kAXMainWindowChangedNotification`、`kAXApplicationActivatedNotification`、`kAXWindowMiniaturizedNotification`、`kAXWindowDeminiaturizedNotification`
- 收到焦点变化 → 把该窗口移到列表索引 0
- **不轮询**：完全事件驱动，空闲时 CPU ≈ 0
- 冷启动时以 CGWindowList 的层级顺序（front-to-back）做初始顺序

可参考 `alt-tab` 的节流做法：面板打开期间的突发 AX 事件走 200ms 节流合并，避免内容抖动。

### 4.4 缩略图捕获

| 方案 | 状态 | 结论 |
|---|---|---|
| `CGWindowListCreateImage` | macOS 14 起**已弃用** | 仅作为最小化窗口的兜底 |
| `SCScreenshotManager.captureImage` + `SCContentFilter(desktopIndependentWindow:)` | 推荐（macOS 14+） | **主路径** |
| `SCStream` 持续流 | 可做实时刷新 | 功耗高，v1 不用；仅展开时按需截 |
| `CGSHWCaptureWindowList`（私有 SkyLight） | 可截最小化窗口 | 可选兜底，注意风险 |

策略（事件驱动缓存，不做持续捕获）：

1. 启动 / 窗口生命周期变化 / 某窗口失焦时，异步刷新其缩略图
2. 后台 `OperationQueue` 并发度 8
3. 展开面板时**立即用缓存渲染**，缺失的瓦片异步补拍，优先补选中项及其相邻项
4. 缓存按窗口 ID 存 `CGImage` + LRU 上限（建议 32 张 / 单张最大 1024px 宽）
5. 高 DPI：内建屏 2x，缩略图按 2x 尺寸截取再下采样

### 4.5 Hover 检测（设计决策）

| 方案 | 优点 | 缺点 |
|---|---|---|
| A. 面板接收鼠标事件（`NSTrackingArea`） | 实现简单 | 会吞掉该区域的所有点击；刘海带虽不可点，但展开面板会覆盖菜单栏 |
| **B. 面板 `ignoresMouseEvents = true` + 全局 `NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved)`** | **不干扰任何其他 App 的鼠标事件**；展开态再临时置 `false` | 需要高频回调，要做廉价判断 + 节流 |

**决策：采用 B**。全局 `mouseMoved` 回调里只做一次 `NSRect.contains(point)` 判断（微秒级），并用 `CACurrentMediaTime()` 做最小间隔节流（如 16ms），不产生额外分配。

展开态为了「不吞掉菜单栏点击」：
- 面板只在「卡片内容实际占据的区域」由多个窗口/区域组成，其余透明区域不接收事件
- 鼠标一旦离开展开面板 + 上方热区，**80ms 内**收起，保证用户点菜单栏时面板已经消失
- 收起动画期间若检测到鼠标按下，立即强制收起并放弃本次点击

### 4.6 窗口切换到前台

三级策略，逐级降级：

1. **公开路径（优先）**：`NSRunningApplication.activate(options: .activateIgnoringOtherApps)` + `AXUIElement.setAttribute(kAXFocusedWindowAttribute)` + `performAction(kAXRaiseAction)`
2. **最小化窗口**：先 `kAXMinimizedAttribute = false` 取消最小化，再 focus
3. **私有路径（兜底，可开关）**：`_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo`（让指定窗口真正成为 key window）。注意：这是私有 API，且部分机型上还需配合 `CGSSetSymbolicHotKeyEnabled`

跨 Space 的窗口：公开 API 无法在不切换 Space 的情况下激活。策略为「激活时切到该窗口所在 Space」，或 v1 直接**把其他 Space 的窗口排在列表末尾并标注 Space 名**，由用户触发切换。→ 归入 M5 待实验证。

### 4.7 权限体系

| 权限 | 用途 | 缺失时的降级 |
|---|---|---|
| 屏幕录制（Screen Recording） | 窗口标题、缩略图 | 无标题（用应用名占位）+ 无缩略图（用应用图标大图标占位）；功能仍可用 |
| 辅助功能（Accessibility） | 窗口枚举、MRU、切换 | **核心能力不可用**，必须引导授权 |

实现要点：
- 屏幕录制权限用 `CGPreflightScreenCaptureAccess()` / `CGRequestScreenCaptureAccess()` 检查与申请
- 无障碍权限用 `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
- **TCC 权限与代码签名身份绑定**：ad-hoc 签名会导致每次重装都需重新授权。开发期必须建立本机固定自签名身份（脚本化），否则调试体验极差
- macOS 15+ 会周期性弹「已允许屏幕录制」提醒；属于系统行为，文档中说明即可

### 4.8 多屏与无刘海机器

- 监听 `NSApplication.didChangeScreenParametersNotification`（分辨率/显示器插拔/缩放变化）→ 重算面板 frame 并重排
- 有刘海屏：面板贴在 `notchFrame`
- 有刘海机型但外接屏：只在内建屏显示
- 无刘海 Mac / 全外接屏：走 fallback（菜单栏中央一段热区，或按设置不启用；可参考 DynamicNotchKit 的 `.floating` 样式）
- 分辨率切换（如本机 1728×1117 是缩放模式）：刘海宽高会变，**再次强调不可硬编码 185×32**

### 4.9 与系统功能的共存

| 系统功能 | 影响 | 对策 |
|---|---|---|
| 前台调度（Stage Manager） | 开启时非当前舞台的窗口被缩到侧边，AX 位置/可见性变化，缩略图可能失真 | v1 检测到 Stage Manager 开启时给出提示；缩略图失败时降级为图标 |
| Mission Control | 进入后所有窗口缩放排布 | 面板随 `canJoinAllSpaces` 一起参与；收起态无影响 |
| **其他 App 全屏** | **需求上要求全屏 App 遮挡我们（F11 唯一例外）** | 不加 `.fullScreenAuxiliary` + 监听 `activeSpaceDidChangeNotification` 主动收起（§4.1.1） |
| 系统通知横幅 / 系统模态弹窗 | level=1000 会盖住它们 | 检测到系统模态或自身弹窗时临时降级 level 到 `.floating`（§4.1.1 第 6 条） |
| 屏幕录制/无障碍授权对话框 | 同上，且必须可点，否则授权流程卡死 | 同上，且此时强制收起面板 |
| 菜单栏隐藏/自动隐藏 | 刘海高度不变，但菜单栏高可能变 | 用 `safeAreaInsets` 为准，不用 `menubarHeight` |
| 其他刘海应用（Boring Notch 等） | 面板层级冲突，互相覆盖 | v1 不做互斥，文档说明冲突；后续可检测进程并提示 |
| 系统原生 ⌘Tab / Dock | 完全不动，平行存在 | 不做键盘钩子拦截（避免复杂度），本项目以「鼠标 + 刘海内键盘」为主 |

### 4.10 性能指标（验收线）

| 指标 | 目标 |
|---|---|
| 空闲 CPU（收起态） | < 0.3%（无轮询，仅 mouseMoved 判定） |
| 展开响应 | 鼠标进入热区 → 首帧显示 ≤ 80ms |
| 缩略图已有缓存时 | 展开即出图，无空壳 |
| 内存 | 常驻 ≤ 120MB，缩略图缓存 ≤ 64MB |
| 展开时 CPU 峰值 | ≤ 25%（单次刷新） |
| Shift 滚轮滚动 | 稳定 60fps，无掉帧、无连跳（130ms 节流） |
| 面板常驻性 | 其他 App 激活/切换 Space/弹模态时面板不消失；仅其他 App 全屏时被遮挡 |

### 4.11 分发与签名（决策）

因为需要 **无障碍 + 屏幕录制**，且大概率用到**私有 API**：

- **不上 Mac App Store**（沙盒 + 私有 API 双重阻断）
- 分发方式：**Developer ID 签名 + 公证（notarization）**，走 Sparkle 自动更新
- 沙盒关闭（`com.apple.security.app-sandbox = NO`），启用 Hardened Runtime
- 私有 API 必须集中在一个 `PrivateAPI/` 目录里，用 `dlopen`/`dlsym` 动态调用并做能力检测，缺一个就降级

### 4.12 技术选型结论

| 决策点 | 结论 |
|---|---|
| 是否用 DynamicNotchKit | **不用**（引入了它的状态机与样式抽象，灵活性受限）。只借鉴其 MIT 许可的几何算法 |
| UI 框架 | AppKit 做窗口/事件（`NSPanel` + 全局事件），SwiftUI 做内容（`NSHostingView`） |
| 最低系统 | macOS 14（`SCScreenshotManager` 需要 14+）；`#available` 分支兼容 13 |
| 语言/并发 | Swift 6，主线程负责 UI + AX 回调；缩略图走后台队列；严格并发检查（`@MainActor` 标注） |
| 项目组织 | Xcode 工程 + SwiftPM 本地包（核心逻辑独立成包，便于单测） |

---

## 5. 架构设计

### 5.1 模块划分

`[x]` = 已实现（截至 v0.3），`[ ]` = 待实现。

```
NotchSwitch/                        SwiftPM 包（ADR-011）
├── Package.swift                   两个 target：NotchKit / NotchSwitch
├── Resources/Info.plist            LSUIElement 等 bundle 元数据
├── scripts/
│   ├── signing.conf                签名身份/钥匙串的共享配置
│   ├── setup-signing.sh            建立本机固定自签名身份（TCC 权限稳定性的前提）
│   ├── build-app.sh                构建 + 组装 .app + 签名（校验 DR 类型）
│   ├── run-app.sh                  构建 + kill 旧实例 + 重启（--install 装到 /Applications）
│   └── reset-permissions.sh        重置本 App 的 TCC 记录（授权失配时用）
├── Sources/NotchKit/               核心逻辑（纯 AppKit，可单测）
│   ├── NotchGeometry.swift             notchFrame / menubarHeight / notchTarget（纯函数）
│   ├── NotchPanel.swift                NSPanel 子类（level/collectionBehavior/层级配置）
│   ├── NotchContentContainer.swift     固定尺寸内容「顶部居中 + 被窗口揭开」+ 滚动捕获
│   ├── LayerGuard.swift                常驻最前台维护：全屏检测、系统模态检测、临时降级
│   ├── HoverMonitor.swift              全局 mouseMoved 热区判定 + 节流 + 丢事件安全网
│   ├── NotchPanelController.swift      几何/展开收起/悬停联动/屏幕变化重排 总控
│   ├── NotchMetrics.swift              几何的 ObservableObject 广播（供 SwiftUI 读取）
│   ├── PanelSelection.swift            预览带位移（120Hz 帧驱动，仅滚动期间存在）
│   ├── ScrollFollow.swift              逐帧跟随 + 松手吸附的数学（纯逻辑，可单测）
│   ├── ScrollDelta.swift               Shift 转轴 + 触控板/滚轮换算（纯逻辑，可单测）
│   ├── PermissionChecker.swift         两项 TCC 权限检查/申请/跳转
│   ├── Log.swift                       os.Logger 统一日志出口（调试主要手段）
│   ├── PrivateAPI/
│   │   └── AXWindowID.swift            dlsym 动态查找 `_AXUIElementGetWindow`
│   └── WindowKit/                      窗口领域模型与系统交互
│       ├── WindowInfo.swift                窗口模型
│       ├── CGWindowSnapshot.swift          CGWindowList 快照（冷启动排序 + 兜底匹配）
│       ├── AXElement+Convenience.swift     AX 属性读写封装
│       ├── WindowEnumerator.swift          AX 枚举 + CG 过滤
│       ├── AXObserverPool.swift            per-app AXObserver 订阅（零轮询）
│       ├── MRUOrder.swift                  MRU 排序（纯逻辑，可单测）
│       ├── WindowListModel.swift           窗口列表 + 节流合并
│       ├── ThumbnailStore.swift            ScreenCaptureKit 截图 + LRU 缓存
│       └── WindowActivator.swift           三级激活策略
├── Sources/NotchSwitch/            应用外壳
│   ├── main.swift                      入口 + setActivationPolicy(.accessory)
│   ├── AppDelegate.swift               装配、辅助窗口、调试文本
│   ├── PermissionsModel.swift          权限状态轮询与申请
│   ├── StatusItemController.swift      菜单栏入口
│   └── UI/
│       ├── NotchRootView.swift             面板内容：横向窗口预览条
│       ├── PermissionGuideView.swift       权限引导
│       └── DebugPanelView.swift            调试面板
└── Tests/NotchKitTests/
    ├── NotchGeometryTests.swift        7 项几何断言（用本机实测数据）
    └── WindowListTests.swift           22 项：MRU / 逐帧跟随吸附 / 滚动归一化 / 预览带位移
```

> 原计划里的 `ScrollWheelCatchView.swift` 未单独落地——改用 `NotchContentContainer` 直接实现（ADR-020）。
> 原计划里的 `SearchKit/` 在 M4 搜索部分实现时再建目录。

> 原计划中的 `SearchKit/`（M4）与 `PrivateAPI/`（M5）在对应里程碑再建目录。

### 5.2 线程模型

| 线程 | 职责 |
|---|---|
| 主线程（`@MainActor`） | 全部 UI、全局鼠标事件、AXObserver 回调、窗口列表变更、缩略图派发回主线程 |
| 后台队列（并发 8） | 仅缩略图捕获与下采样 |
| 定时器 | **无**（禁用轮询；节流用时间戳比较实现） |

### 5.3 数据流

```
AXObserver 事件 ─┐
NSWorkspace 事件 ─┼→ WindowListModel（主线程，MRU 排序）─→ SwiftUI 视图
CGWindowList 扫描 ┘                │
                                   └→ ThumbnailStore 异步补图 ─→ 主线程更新
鼠标进入热区 ─→ HoverMonitor ─→ NotchPanelController 展开 ─→ 视图按缓存立即渲染
```

### 5.4 关键数据结构

```swift
struct WindowInfo: Identifiable {
    let id: CGWindowID
    let axElement: AXUIElement        // 可操作句柄
    let pid: pid_t
    let bundleId: String?
    let appName: String
    var title: String
    var isMinimized: Bool
    var isFullScreen: Bool
    var spaceID: Int?                 // 私有 API 探测，可空
    var lastFocusOrder: Int
    var thumbnail: CGImage?           // 仅存缓存版本（已下采样）
    var appIcon: NSImage?
}
```

---

## 6. 交互设计规格

### 6.1 尺寸规格（pt，可配置）

| 元素 | 收起态 | 展开态 |
|---|---|---|
| 面板（收起态） | 刘海矩形 = 185×32（本机） | — |
| 可视卡片数 | — | **固定 4 张**（单行不换行；设置项可调 3~6） |
| 小预览卡片 | — | 176×110 图片 + 22 标题行 = 176×132 |
| 展开面板宽 | — | `16×2(内边距) + 4×176 + 3×12(间距)` = **772**（本机屏宽 1728，占比 45%） |
| 展开面板高 | — | 卡片 132 + 上下内边距 16 = **148**（面板整体 148 + 顶部留白 33 = 181） |
| 大预览 | — | 按窗口原始比例缩放，最大 640×400；下方信息行高 34 |
| ~~溢出指示~~ | — | **已移除**（2026-09-14：移除底部状态栏，面板只展示窗口卡片）。后果见 R17：窗口多于 4 个时没有任何提示 |
| ~~应用筛选条~~ | — | **已移除**（同上；F7 若要恢复需重新评估面板高度） |
| 圆角 | 贴合刘海用自绘反向圆角 | 底部两角 `bottomLeading/bottomTrailing = 18` |

### 6.2 视觉与材质

- macOS 26+：**Liquid Glass 已落地**：`.glassEffect(.regular, in:)`，唯一入口 `KimiTheme.kimiGlass`（见 ADR-023）
- macOS 14/15：回退 `.ultraThinMaterial`（同一入口内分支）
- 品牌色：Kimi 蓝 `#4D6BFE` → 紫 `#8B5CF6` 渐变，**只做小面积点缀**（悬停描边、图标底、空态徽标），大面积一律中性玻璃
- 收起态**完全不绘制内容**（零视觉侵入），可选：鼠标进入时 32pt 高的刘海下方出现 1pt 高亮线作为反馈
- 动画：`NSAnimationContext` 或 SwiftUI `withAnimation`，`easeOut` 0.16~0.20s；大预览用 `scaleEffect(0.96 → 1) + opacity`
- 深色/浅色模式自动跟随；强调色跟随系统

### 6.3 时序参数

| 事件 | 延迟 |
|---|---|
| 进入热区 → 展开 | 0ms（立即，或 40ms 防误触，可配置） |
| 悬停卡片 → 弹出大预览 | 280ms |
| 鼠标离开面板 → 收起 | 240ms（滞回，避免抖动） |
| 鼠标离开后强制收起上限 | 80ms（用于让出菜单栏点击） |
| 滚动跟随时间常数 τ | 0.035s（90% 收敛 ≈ 80ms） |
| 滚动驱动帧率 | 120Hz，仅滚动期间存在 |
| 松手后的停位 | 原地（无吸附、无回弹） |
| AX 事件节流窗口 | 200ms |

### 6.4 键盘

| 按键 | 行为 |
|---|---|
| 任意字母/数字 | 直接进入搜索（无需点输入框） |
| 中文输入法 | 拼音过程中即可匹配（读 IME 未上屏串） |
| ← → ↑ ↓ | 移动选择，大预览跟随 |
| Return | 打开选中窗口；无窗口则启动匹配到的 App |
| Esc | 第一次清空搜索，第二次收起面板 |
| Tab | 在「窗口区 / 应用筛选条」间切换焦点 |
| 滚轮 / 双指滑动 | 卡片多于 4 张时连续滚动可视区（见 §6.5，不需要按 Shift） |

### 6.5 Shift + 滚轮滚动交互（F12）

**触发条件**：面板已展开 → 卡片总数 > 可视数（4）→ 鼠标位于面板内 → **直接滚动，不需要按 Shift**。

**行为定义**

| 操作 | 行为 |
|---|---|
| 滚轮 / 双指上下滑 | 预览带连续水平位移，**跟手**，不是逐张跳 |
| 双指左右滑 | 同上（横向浏览最自然的手势） |
| Shift + 滚轮 | 同样有效（macOS 会把垂直转轴成水平） |
| 松手后 | 停在哪里就是哪里，**不做吸附**（允许停在半张卡中间） |
| 到达边界 | 硬夹紧，不做循环、不做回弹 |
| 位移时的可见区 | `firstVisibleIndex` / `visibleRange` 跟随更新（大预览导航用） |
| 卡片 ≤ 4 张 | `maxOffset == 0`，**不消费事件**（让滚动继续传给下层，不白白吞掉） |

**实现要点（4 个坑）**

1. **渲染方式必须是「所有卡片排成一长条 + 整体位移」，不能是「换一批卡片」。**
   换一批在视觉上是内容瞬变——无论帧率多高都是「跳」。
   这是「不丝滑」的**根本原因**，改参数救不回来。对应：
   ```swift
   HStack { ForEach(windows) { card($0) } }
       .padding(.horizontal, 16)
       .offset(x: -selection.offset)
       .frame(width: panelWidth, alignment: .leading)
       .clipped()
   ```

2. **必须用 `NSView.scrollWheel(with:)`（放在 `NotchContentContainer` 上），不能用 `NSEvent.addLocalMonitorForEvents` 单独顶事。**
   面板是 `nonactivatingPanel`，本 App 不处于 active 状态；鼠标位于面板之上时滚动事件会直接派发到该窗口的视图层级，不依赖 App 激活状态。
   另外 `NSHostingView` 有可能吞掉事件，所以**两条路径都装**（容器 + local monitor），用**事件时间戳**去重。

3. **Shift 会把滚轮「转轴」**：macOS 在按住 Shift 时会把垂直滚轮映射为水平 delta，必须双轴取值：
   ```swift
   let d = deltaX != 0 ? deltaX : deltaY
   ```
   只读 `scrollingDeltaY` 会拿到 0（**最典型的踩坑点**）。

4. **不按 Shift 分情况，改用「主导轴」判定**：三种输入都会自然落到「某个轴绝对值明显更大」上——普通滚轮 / 双指上下滑是垂直占优，双指左右滑与 Shift 转轴是水平占优。取绝对值大的那个轴即可统一处理。

5. **触控板与机械滚轮的 delta 量纲不同，必须分开换算**：
   - 触控板（`hasPreciseScrollingDeltas == true`）：delta 是**点**，**1:1 跟手，不做任何缩放**——缩放是丝滑感的敌人
   - 机械滚轮（`false`）：delta 是**行数**（通常一格 = 1），必须乘行高 44pt 换算成点。
     **不换算的话一格只走 0.55pt，表现为「滚轮几乎没反应」**
   - 不同鼠标一格上报的行数不同（1 / 3 / 10 都有），单次位移封顶 ±120pt

**平滑算法（`ScrollFollow`）**

```
offset += (target - offset) × (1 − exp(−dt / τ))      τ = 0.035s
```

- 用**时间常数**而不是「每帧固定比例」：ProMotion 是 120Hz、普通屏 60Hz，固定比例会让两种屏手感完全不同
- 定时器 120Hz，仅在滚动期间存在，停下即销毁（空闲零开销）
- **不做吸附**：滚到哪里就停在哪里。`firstVisibleIndex` 用 `rounded()` 从偏移量反推，只影响「可见区从第几张算起」，不会反过来移动内容

**与 hover 大预览的关系**：滚动期间抑制「悬停 280ms 弹大预览」的计时器，避免滚动过程不断闪烁；滚动停止后再恢复计时。

### 6.6 层级优先级（自上而下）

```
1. 系统级 UI（登录窗、切换用户、Control Center 展开、Mission Control 动画）
2. 其他 App 的全屏窗口          ← 唯一能遮住我们的（F11 的例外）
3. [本项目] 面板  (level = .screenSaver / 1000)
4. 系统通知横幅、系统模态弹窗    ← 通过临时降级 level 主动让出（§4.1.1 第 6 条）
5. 菜单栏、状态栏  (24 / 25)
6. 其他 App 普通窗口  (0)
```

---

## 7. 里程碑路线图

> 时间以 2026-09-14 为起点，单人全职假设；每个里程碑都有**可验收的产出**。

### M0 · 骨架与探测（0.5 天）— 09-15 ~ 09-16 · **已完成**

- [x] SwiftPM 工程（替代 .xcodeproj，见 ADR-011），`LSUIElement = true`（无 Dock 图标、不进 ⌘Tab）
- [x] 菜单栏 `NSStatusItem`：展开/收起、权限状态、调试面板、权限引导、退出
- [x] 权限引导窗口（无障碍 + 屏幕录制，带「申请授权」与「打开系统设置」按钮）
- [x] **调试面板**：所有屏幕的 frame/visibleFrame/safeAreaInsets/aux 区/notchFrame/menubarHeight + 面板实时状态
- [x] `scripts/setup-signing.sh`：建立本机固定自签名身份
- [x] `scripts/build-app.sh`：构建 + 组装 .app + 签名
- **验收结果**：`swift build` 通过、`swift test` 7/7 通过、`.app` 冒烟测试运行 5 秒无崩溃（见 §13）

### M1 · 刘海贴片 + 悬停展开收起（2 天）— 09-17 ~ 09-20 · **代码已完成，待人工验收**

- [x] `NotchPanel` 按 §4.1 配置，贴在内建屏刘海位置（多屏 + 无刘海 fallback）
- [x] **常驻最前台（F11）**：`level = .screenSaver` + `hidesOnDeactivate = false` + `isFloatingPanel = true`
- [x] **全屏例外处理**：`LayerGuard` 监听 `activeSpaceDidChangeNotification` + 1Hz 看门狗，全屏时自动收起
- [x] **反向保护**：自身辅助窗口 / 系统模态弹窗出现时临时降级 level 到 `.floating`
- [x] `HoverMonitor`：全局 + 本地 mouseMoved 双监听判定热区，进出触发展开/收起，含丢事件安全网
- [x] 展开/收起动画（0.22s，宽度与高度同时从刘海矩形向外长大）
- [x] 占位内容（4 张占位卡 + 应用筛选条 + `Shift + 滚轮翻卡` 提示）
- [ ] 反向圆角接缝（自绘 Path 贴合刘海曲线）—— 留到 M5 打磨
- **待人工验收**（代码写完不等于验收通过，需在真机上逐条确认）：
  1. 其他 App 激活 / 切换 Space 时面板不消失
  2. 其他 App 全屏时面板被遮挡且不响应悬停，退出全屏后自动恢复（Q7）
  3. 权限授权对话框不被自己的面板遮挡（Q9 / R13）
  4. 空闲 CPU < 0.3%（活动监视器观察）
  5. 无刘海机型 / 外接屏不崩（本机外接屏可验证 fallback 分支）
  6. 面板展开时是否明显妨碍菜单栏使用（Q5）

### M2 · 窗口枚举 + MRU + 切换（3 天）— 09-21 ~ 09-26

- [ ] `WindowEnumerator`：AX 拿窗口列表 + CG 过滤（layer/alpha/尺寸/排除自身）
- [ ] `AXObserverPool`：订阅 7 类通知，事件驱动维护列表
- [ ] `WindowListModel`：MRU 排序 + 200ms 节流合并
- [ ] 卡片列表 UI：应用图标 + 标题（无屏幕录制权限时降级显示）
- [x] `WindowActivator`：三级激活策略（含最小化取消）
- **验收结果**：实测枚举到 **9 个窗口 / 6 个应用**，`_AXUIElementGetWindow` 可用（Q1 确认）；点击切换待人工确认

### M3 · 缩略图与大预览（3 天）— 09-27 ~ 10-02 · **缩略图完成，大预览待做**

- [x] `ThumbnailStore`：`SCScreenshotManager` + `SCContentFilter(desktopIndependentWindow:)`
- [x] LRU 缓存（32 张上限）+ 展开时先渲染缓存、缺失异步补拍
- [x] 小预览卡片的 16:10 裁切与圆角
- [ ] **大预览浮层**（延迟 280ms 弹出，跟随键盘选择）—— 待做，这是本项目的核心差异点
- [x] 最小化窗口降级为应用图标 + 最小化角标
- [ ] 并发 8（当前是顺序捕获 + `Task.yield()`，大窗口数时会偏慢，待优化）
- **待人工验收**：展开后卡片是否显示真实画面；内存是否 ≤ 120MB

### M4 · 搜索与键盘（2 天）— 10-03 ~ 10-06 · **进行中**

- [x] **Shift + 滚轮滚动（F12）**：一长条卡片 + 连续像素位移 + 120Hz 指数跟随（τ=0.035s）+ 松手吸附；触控板 1:1、滚轮 ×0.55；双路径事件捕获 + 时间戳去重
- [ ] 直接键入搜索 + 高亮匹配
- [ ] 中文全拼 / 首字母 / 模糊匹配（自建轻量索引，不依赖 Spotlight）
- [ ] 方向键 / Return / Esc / Tab 完整支持
- [ ] 应用筛选条
- [ ] 可启动未运行的 App（扫描 `/Applications`、`/System/Applications`、`~/Applications`，支持新增后刷新）
- **待人工验收**：卡片超 4 张时 Shift 滚轮能否稳定逐张前后滚动（Q8）；滚动实现有两条路径（容器 + local monitor），需确认没有重复步进

### M5 · 打磨与分发（4 天）— 10-07 ~ 10-14

- [ ] 设置页（热区尺寸/位置、展开延迟、行数、排序偏好、开机自启）
- [ ] 跨 Space / 全屏窗口激活策略实验与落地
- [ ] 与前台调度（Stage Manager）共存的降级处理
- [ ] 多屏热插拔 / 分辨率切换回归
- [ ] 本机固定自签名身份脚本（避免每次重装重新授权）+ Developer ID 签名 + 公证
- [ ] Sparkle 自动更新 + `appcast.xml`
- [ ] 单测（`NotchKit` 几何、MRU 排序、搜索匹配）+ 手动验收清单
- [ ] v0.1.0 发布
- **验收**：全新机器下载 → 安装 → 授权 → 可用，全流程无卡点

---

## 8. 风险登记表

| # | 风险 | 等级 | 影响 | 对策 |
|---|---|---|---|---|
| R1 | 窗口标题受屏幕录制权限限制 | 高 | 无标题无法区分同应用多窗口 | 引导授权；未授权时用「应用名 + 序号 + 缩略图」降级 |
| R2 | 无公开 MRU API，需自建 | 高 | 排序不准 = 核心体验崩 | 事件驱动 AXObserver；冷启动用 CG 层级序；加「最近使用」兜底持久化到 UserDefaults |
| R3 | 最小化窗口无法用 ScreenCaptureKit 捕获 | 中 | 该卡片无图 | 降级应用图标；可选私有 `CGSHWCaptureWindowList` |
| R4 | 跨 Space / 全屏窗口激活受限 | 高 | 点了切不过去 | 公开 API 优先，必要时先切 Space 再激活；v1 明确标注跨 Space 窗口 |
| R5 | 私有 API 的可用性/合规风险 | 中 | 上架无望 + 系统更新可能失效 | 集中隔离 + 动态调用 + 能力检测 + 降级；接受「不上架」 |
| R6 | 与前台调度同时开启冲突 | 中 | 缩略图失真、切换异常 | 检测到开启时提示；缩略图失败降级 |
| R7 | 面板吞掉菜单栏点击 | 中 | 体验割裂 | 收起态 `ignoresMouseEvents`；展开态 80ms 内让出；面板外区域不接收事件 |
| R8 | 展开期间内容抖动 | 中 | 观感差 | 200ms 节流合并 + 展开期间冻结重排（保留选中项与原顺序） |
| R9 | 功耗/内存（缩略图） | 中 | 笔记本续航 | 不做持续 SCStream；事件驱动 + LRU + 下采样 |
| R10 | ad-hoc 签名导致反复重新授权 | 中 | 开发效率极低 | M0 阶段就建立本机固定自签名身份脚本 |
| R11 | macOS 版本迭代导致 API 变化（26→27 已改视觉层） | 低 | 兼容问题 | 所有 API 用 `#available` 分支；几何全部运行时计算不硬编码 |
| R12 | 与其他刘海应用层级冲突 | 低 | 互相覆盖 | 不做互斥；文档说明；后续可检测进程提示 |
| R13 | 常驻最前台误遮挡系统弹窗/授权框 | **高** | 用户无法点授权，流程卡死 | 检测系统模态 + 自身弹窗时临时降级 level；屏幕录制授权时强制收起（§4.1.1 第 6 条） |
| R14 | `nonactivatingPanel` 下用 local monitor 收不到滚轮事件 | 中 | F12 交互直接失效 | 必须用 `NSView.scrollWheel(with:)`（§6.5 第 1 点） |
| R15 | Shift 滚轮转轴导致 delta 读取为 0 | 中 | 滚动无响应 | 双轴取值 `scrollingDeltaX != 0 ? X : Y`（§6.5 第 2 点） |
| R16 | `canJoinAllSpaces` 在全屏 Space 中仍显示面板 | 中 | 与 F11「全屏例外」冲突 | M1 实测（Q7）；兜底用 `activeSpaceDidChange` 主动 `orderOut` |
| R17 | 可视区仅 4 张 → 窗口多时发现性下降 | **高**（已升级） | 实测 9 个窗口时只有 4 个可见，且**面板内已无任何提示**（底部状态栏与 `3/9` 计数已被移除） | 待定方案：① 右边缘露出下一张卡的窄条（不占额外高度、最自然）；② 两侧渐隐遮罩；③ 首次使用提示「Shift + 滚轮」 |

---

## 9. 决策记录（ADR）

| ID | 决策 | 理由 | 日期 |
|---|---|---|---|
| ADR-001 | 采用「自研 NSPanel 贴片」而非引入 DynamicNotchKit | 需要完全控制展开动画、多窗口区域、事件穿透与激活流程，库的抽象会限制 | 2026-09-14 |
| ADR-002 | 不复制任何 GPL 项目代码（boring.notch / DockDoor / alt-tab-macos） | 避免 GPL 传染 | 2026-09-14 |
| ADR-003 | hover 检测用「全局 mouseMoved + 矩形判定」而非面板接收事件 | 收起态零干扰，不吞任何点击 | 2026-09-14 |
| ADR-004 | 不上 Mac App Store，走 Developer ID + 公证 + Sparkle | 需无障碍/屏幕录制权限，且大概率用私有 API | 2026-09-14 |
| ADR-005 | 最低支持 macOS 14 | `SCScreenshotManager` 门槛（14+ 的 ScreenCaptureKit 单帧 API 更干净） | 2026-09-14 |
| ADR-006 | 缩略图事件驱动缓存，不做持续 SCStream | 续航与散热优先，展开响应由缓存保证 | 2026-09-14 |
| ADR-007 | 不拦截系统 ⌘Tab | 内核对 `CGEventTap` 全权接管复杂度高，且与原生行为冲突风险大 | 2026-09-14 |
| ADR-008 | 常驻最前台 = `level=.screenSaver` + `hidesOnDeactivate=false` + `isFloatingPanel=true` + **不加** `.fullScreenAuxiliary` | 「不被任何窗口遮挡」由 level 保证；「其他 App 全屏时被遮挡」恰好由「不加 fullScreenAuxiliary」实现；`hidesOnDeactivate` 必须显式关掉否则失去不消失特性 | 2026-09-14 |
| ADR-009 | 可视区固定 4 张 + Shift+滚轮逐张滚动，**放弃 2 行网格** | 4 张的横向占比（772 / 1728 ≈ 45%）与刘海的视觉比例最协调；多行网格与「前后翻」的心智冲突，且会让面板高度在 1/2 行之间跳变 | 2026-09-14 |
| ADR-010 | Shift+滚轮用 `NSView.scrollWheel(with:)` 实现，不用 `NSEvent` local monitor | 面板为非激活面板，App 非 active 时 local monitor 收不到事件；窗口内 view 的滚动事件派发不依赖 App 激活状态 | 2026-09-14 |
| ADR-011 | 用 SwiftPM 包 + 脚本组装 .app，**不手写 .xcodeproj** | 手写 pbxproj 易错且难维护；`swift build` / `swift test` 可在纯命令行下闭环验证。Xcode 可直接打开 `Package.swift`，需要时再补工程文件。代价：需自己维护 `build-app.sh` 与 Info.plist | 2026-09-14 |
| ADR-012 | 内容视图固定为展开尺寸，由窗口裁剪出「揭开」效果（`NotchContentContainer`） | 若让 SwiftUI 内容跟随窗口尺寸变化，动画过程中 4 张卡片会被反复压缩重排，视觉上是「挤出来」而不是「长出来」。固定内容 + 顶部居中定位 + 窗口裁剪，得到干净的生长动画且不触发内容重排 | 2026-09-14 |
| ADR-013 | 内容顶部留白 = `max(刘海高度, 菜单栏高度)` | 本机上二者为 32 / 33pt，相差 1pt。取较大值可确保内容永不压到菜单栏，同时收起态（窗口高 = 刘海高）仍然完全透明不漏内容 | 2026-09-14 |
| ADR-014 | `level` 必须在 `NSPanel` 初始化的**最后**一步设置；并在 `start()` 里显式 `applyLevel()` 一次 | `isFloatingPanel` 的 setter 会顺手把 window level 改成 `.floating`(3)，写在 `level = .screenSaver` 之后会**静默覆盖**它。实测踩中过：面板层级变成 3，被菜单栏(24)压住，UI 上只表现为「东西不见了」 | 2026-09-14 |
| ADR-015 | 权限未齐时**每次启动都**自动打开引导窗口，不做「只提示一次」 | 辅助功能的系统提示**每次启动只弹一次**。一旦用「只提示一次」的持久化标记，用户关掉窗口后就再也没有入口，等于把授权路径堵死（实测踩中）。宁可每次启动多一个窗口，也不能让用户无路可走 | 2026-09-14 |
| ADR-016 | 不提供 App 内「一键重置 TCC」按钮，改为脚本 `scripts/reset-permissions.sh`；但 App 内提供「重启 NotchSwitch」与「运行位置」提示 | 重置 TCC 会让当前授权立刻失效、且必须重启，做成一个菜单项容易误触；而「授权后重启」是常规操作，值得放进 UI | 2026-09-14 |
| ADR-017 | 签名身份放在**独立钥匙串**（口令固定），而不是登录钥匙串；**不做** `add-trusted-cert` | 登录钥匙串口令是用户登录密码，导入/访问会弹 GUI 密码框，脚本化必然卡住或失败。独立钥匙串全程无交互。自签名证书**不需要**加入系统信任：签名只需私钥+证书，信任只影响 Gatekeeper 启动校验，而本地构建的 App 没有 quarantine 标记 | 2026-09-14 |
| ADR-018 | 导入证书用**分别导入 PEM**（私钥 + 证书），彻底弃用 p12 | OpenSSL 3.x 默认用 AES-256/SHA-256 导出 p12，macOS 的 `SecKeychainItemImport` 只认老的 RC2/3DES + SHA-1，直接报 `MAC verification failed during PKCS12 import`。分开导入 PEM 可完全绕开这个不兼容 | 2026-09-14 |
| ADR-019 | 统一从 `/Applications/NotchSwitch.app` 运行，`--install` 后删除 `build/` 副本 | 同一 bundle id 存在两份时，LaunchServices 可能解析到旧路径——实测 `open /Applications/...` 实际跑起来的却是 `build/` 里那份。TCC 按「路径 + 签名」记录，两份就是两套授权，必然混乱 | 2026-09-14 |
| ADR-020 | 滚动事件放在 `NotchContentContainer`（NSView）上，并额外挂一个 local monitor，用**事件时间戳**去重 | ADR-010 已决定用 `scrollWheel(with:)`，但落到 SwiftUI 里有个新问题：SwiftUI 内容大多由 layer 绘制、没有独立 NSView，包 `NSViewRepresentable` 会被 `NSHostingView` 挡在中间。放在容器上可吃到沿响应者链上浮的事件；再补一个 local monitor 兜底（NSHostingView 有吞掉事件的可能）。两条路径都会收到同一个事件，用 timestamp 去重保证只处理一次 | 2026-09-14 |
| ADR-021 | 滚动改为「一长条卡片 + 连续像素位移 + 帧同步跟随 + 松手吸附」，**废弃整数步进方案**（原 `ScrollStepAccumulator` 已删除） | 原方案的 `offset = 索引`，切卡时整条内容瞬变，视觉上必然是「跳」——调阈值/节流都救不回来。改为连续位移后是真正的滑动。同时把「每帧固定比例」换成**时间常数**，否则 60Hz 与 120Hz 屏手感不一致 | 2026-09-14 |
| ADR-022 | 滚动**不再要求按住 Shift**；轴向改用「主导轴」判定（取绝对值大的轴）；无溢出时**不消费**滚动事件 | 要求按 Shift 会让人以为「滚不动」——面板本身就是横向滚动区，直接滚更符合直觉。三种输入（普通滚轮 / 双指滑动 / Shift 转轴）用主导轴即可统一处理，不必分情况。另外卡片 ≤ 4 张时没有任何可滚动内容，此时吞掉滚动属于无谓打扰 | 2026-09-14 |
| ADR-023 | **取消松手吸附**，滚到哪里就停在哪里（`ScrollFollow.snap` 已删除） | 吸附会在松手瞬间把内容再拽一下——用户刚把内容停在想看的半张卡上，它自己滑走了，这正是「不够跟手」的来源。跟手感优先于「停位整齐」 | 2026-09-14 |
| ADR-023 | **UI 材质统一走 `KimiTheme.kimiGlass`**：macOS 26+ 用 `.glassEffect`（Liquid Glass），14/15 回退 `.ultraThinMaterial`；品牌渐变只做小面积点缀；改版**不动任何几何与交互参数** | 「26 玻璃 / 低版本模糊」的 `#available` 分支只写一处，视图层不重复判断；玻璃材质与 Tahoe 菜单栏融合是核心观感（§2.3 差异化第 2 条）；滚动/展开手感已调通（v0.9/v0.10），视觉改版不碰布局尺寸、位移与动画时序，避免回归 | 2026-09-14 |
| ADR-024 | 滚动方向：`ScrollDelta.stripOffset` 对主导轴 delta **统一取反**后再喂给预览带 | NSEvent 遵循「+ = 回退」（垂直 + = 向上滚，水平 + = 向左滑）；系统已按用户「自然滚动」设置翻转过符号，所以取反一次就自动跟随系统设置，不需要自己读偏好键。语义定为「下滚 / 左滑 = 前进（露出后面的卡片）」，与所有横向轮播一致 | 2026-09-14 |
| ADR-025 | 窗口过滤改为**严格 `subrole == AXStandardWindow`**（`nil` 也拒） | 实测访达的 AX 窗口列表会多报一个全屏桌面元素（`subrole=nil`、title=nil、frame 盖住整个桌面），旧条件「有 subrole 且不等于 StandardWindow 才拒」放它过去了，多出一张假卡片。用户窗口的 subrole 恒为 AXStandardWindow，严格相等即根因修复 | 2026-09-14 |

---

## 10. 开放问题（待验证）

| # | 问题 | 计划验证时点 |
|---|---|---|
| ~~Q1~~ | ~~私有 `_AXUIElementGetWindow` 在当前 macOS 27 上是否仍可用？~~ **已确认可用**（2026-09-14 实测，日志 `windowID 映射=私有API`） | ✅ 已完成 |
| Q2 | 跨 Space 窗口能否用 `_SLPSSetFrontProcessWithOptions` 直接激活而不切 Space？ | M5 |
| Q3 | macOS 26/27 的 Liquid Glass 菜单栏下，材质用哪种组合观感最好？ | M1 |
| Q4 | 前台调度开启时，AX 窗口列表与缩略图的实际表现如何？ | M5 |
| Q5 | 展开面板上方是菜单栏，是否存在「必须让出菜单栏交互」的真实用户场景？ | M1 可用性测试 |
| Q6 | 全局 mouseMoved 在快速甩鼠标时是否丢事件（导致面板不收起）？ | M1 |
| Q7 | `canJoinAllSpaces` 的窗口在其他 App 的全屏 Space 中是否仍可见？若可见，`activeSpaceDidChange` 兜底的收起是否够及时？ | M1 |
| Q8 | `scrollWheel(with:)` 在 `nonactivatingPanel` + 非 key 窗口上能否稳定收到 Shift 滚轮事件（含触控板双指）？ | M4 |
| Q9 | `level = .screenSaver` 是否会遮挡系统权限授权对话框（导致授权流程卡死）？降级到 `.floating` 的时机能否可靠检测？ | M1 |

---

## 11. 调研资料索引

**官方文档**
- `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` / `auxiliaryTopRightArea` — 刘海几何（macOS 12+）
- `NSPanel` / `NSWindow.StyleMask.nonactivatingPanel` / `NSWindow.Level`
- `SCScreenshotManager` / `SCContentFilter(desktopIndependentWindow:)` / `SCStreamError.userDeclined`
- `CGWindowListCopyWindowInfo`（`kCGWindowName` 需屏幕录制权限）
- `AXUIElement` / `AXObserver` / `AXIsProcessTrustedWithOptions`
- `NSEvent.addGlobalMonitorForEvents(matching:)` / `NSEvent.scrollingDeltaX`·`scrollingDeltaY` / `hasPreciseScrollingDeltas` / `NSView.scrollWheel(with:)`
- `NSWindow.hidesOnDeactivate` / `isFloatingPanel` / `worksWhenModal` / `NSWindow.Level.screenSaver`
- `NSWindow.CollectionBehavior.fullScreenAuxiliary`（**本项目明确不使用**，用于实现「全屏例外」）
- `NSWorkspace.activeSpaceDidChangeNotification`（全屏 Space 检测）
- Apple: *Distribute outside the Mac App Store*（公证）
- WWDC26 macOS 指南（macOS 27：SwiftUI 惰性堆栈/滚动、App Intents、Liquid Glass 视觉；**未见刘海/窗口管理相关新 API**）

**参考实现**
- `MrKai77/DynamicNotchKit`（MIT）— 刘海几何算法 + panel 配置的权威来源
- `louislili/MacDock`（MIT）— 最接近的竞品，刘海窗口切换器
- `kaikozlov/alt-tab` ARCHITECTURE.md — 窗口枚举 / MRU / 缩略图 / 激活的完整架构说明（思路参考）
- `ejbills/DockDoor`（GPL-3.0）、`boring.notch`（GPL-3.0）、`alt-tab-macos`（GPL-3.0）— **仅读思路**

**技术要点来源**
- 「macOS 瀏海 Overlay 实现技术分析」(zyx1121/kilo-agent) — panel 配置与 7 条实战坑点（其中「`NSHostingView` 必须撑满 panel」最易踩）
- NotchNest: 「macOS Tahoe 与刘海：有何新变化」— Tahoe 只改视觉层，未新增刘海交互 API

---

## 12. 下一步（立即行动）

1. 建 Xcode 工程 `NotchSwitch`，`LSUIElement = true`，AppKit + SwiftUI 混合
2. 实现 `ScreenGeometry` + 调试面板，跑通 §3 的实测数据校验
3. 写 `scripts/setup-signing.sh`：创建本机固定自签名身份（**这一步不做，后面每次授权都会痛**）
4. ~~进入 M1：`NotchPanel` + `HoverMonitor` + 展开收起动画~~ —— 已完成，见 §13
5. **当前待办**：按 §7 M1 的 6 条人工验收清单逐条确认，通过后进入 M2（窗口枚举 + MRU + 切换）
6. 验收通过后建议先补一件事：`./scripts/setup-signing.sh`（**M2 开始就需要辅助功能权限，没有固定签名身份会反复重新授权**）

---

## 13. 实现与验收记录

### 13.1 M0 / M1 落地结果（2026-09-14）

| 检查项 | 命令 | 结果 |
|---|---|---|
| 编译 | `swift build` | 通过，0 error / 0 warning（Swift 6 严格并发） |
| 单测 | `swift test` | 7/7 通过（刘海几何 + 菜单栏高度，含边界与异常数据） |
| 打包 | `./scripts/build-app.sh` | 通过，产出 `build/NotchSwitch.app`，签名校验 valid |
| 冒烟测试 | 直接运行 .app 内可执行文件 5 秒 | 正常运行，无崩溃 |

### 13.2 实现过程中的关键结论（值得记下来）

1. **`kAXTrustedCheckOptionPrompt` 在 Swift 6 下不可用**：它被导入为可变的全局 `var`，
   严格并发会报 `not concurrency-safe`。改用字符串字面量 `"AXTrustedCheckOptionPrompt"`
   作为字典 key（这正是该常量的实际值）。
2. **面板必须同时监听全局与本地 mouseMoved**：只装全局监听的话，鼠标移到**我们自己的面板**上时收不到事件，
   热区状态机就会卡在「已进入」而不更新。
3. **丢事件的兜底不能省**：全局 mouseMoved 在快速甩鼠标时可能丢事件，
   结果是面板该收起却收不起来——这是体验上最难受的 bug。故加了 1Hz 安全网
   （仅在「超过 1.5s 无任何事件」时才做一次校正，空闲零开销）。
4. **`NotchMetrics` 是必需的解耦件**：SwiftUI 内容要先于控制器创建，
   但又需要读取运行时算出的顶部留白，用 ObservableObject 单向广播把这个循环依赖拆开了。
5. **`.app` 包内运行 vs `swift run`**：不带 bundle 运行没有 bundle identifier，
   TCC 权限行为不一致（可能不弹窗、授权不生效）。**验证权限相关功能必须用 `build/NotchSwitch.app`。**
6. **【最重要】`isFloatingPanel` 会静默改写 window level**：实测日志打出 `level=3`
   （浮动），而不是预期的 1000。原因是 `NotchPanel.init` 里 `level = .screenSaver` 写在
   `isFloatingPanel = true` **之前**，被 setter 覆盖了。后果是面板被菜单栏(24) 压住，
   而 UI 上的表现只是「东西不见了」，几乎无法反推原因。修法：`level` 放到 init 最后一步，
   并在 `start()` 里显式 `applyLevel()` 一次（见 ADR-014）。
   → **教训：冒烟测试只证明「没崩」，不证明「对」。** 这个 bug 是靠日志打数值发现的，
   所以「常驻最前台」这类看不见的层级约束，必须有日志留痕。

### 13.3 尚未验证（风险最高的几项）

以下都依赖真机人工确认，是 M1 验收的重点，也是目前最大的不确定性来源：

- Q5 面板展开时是否明显妨碍菜单栏使用（当前实现会覆盖菜单栏中央 772pt）
- Q7 `canJoinAllSpaces` 在其他 App 全屏 Space 中的实际表现
- Q9 `level = .screenSaver` 是否会遮挡系统授权对话框
- 空闲 CPU 是否真的 < 0.3%（`HoverMonitor` 节流与 `LayerGuard` 1Hz 看门狗的实际开销）
- 展开/收起动画在 ProMotion 屏上的观感（当前为 0.22s 定时曲线，后续可考虑换成弹簧）

---

## 14. 调试手册

### 14.1 三种运行方式（用途不同，别混用）

| 方式 | 命令 | 什么时候用 |
|---|---|---|
| **打包运行（默认）** | `./scripts/run-app.sh` | 一切与**权限、层级、全屏例外**相关的验证。有 bundle identifier，TCC 行为才正确 |
| 前台直跑 | `build/NotchSwitch.app/Contents/MacOS/NotchSwitch` | 只看 stdout/stderr、看崩溃现场。Ctrl+C 结束。**权限状态不可信**（见下） |
| Xcode 断点 | `xed .`（用 Xcode 打开这个包） | 要打断点、单步、看调用栈 |

- `run-app.sh` 传 `debug` 可构建 debug 版；传 `--no-build` 只重启
- **不要用 `swift run` 或直接执行 `Contents/MacOS/NotchSwitch` 来验证权限**：
  这种启动方式会**继承终端进程的 TCC 归因**，把「其实没授权」误判成「已授权」。
  实测同一份构建：终端直跑报 `辅助功能=true`，经 `open` 启动报 `辅助功能=false`。

### 14.2 日志（首选手段）

```bash
# 实时跟踪重要事件（展开/收起/层级变化/屏幕变化）
/usr/bin/log stream --predicate 'subsystem == "com.notchswitch.app"'

# 含高频细节（悬停进出、level 变更）
/usr/bin/log stream --debug --predicate 'subsystem == "com.notchswitch.app"'

# 回看最近 2 分钟
/usr/bin/log show --last 2m --info --predicate 'subsystem == "com.notchswitch.app"'
```

> **坑**：zsh 里 `log` 是一个内建命令，直接敲 `log ...` 会报 `too many arguments`。
> **必须写全路径 `/usr/bin/log`。**

日志分类：`app` 生命周期 / `panel` 几何与展开收起 / `hover` 悬停 / `layer` 层级守卫。
启动时会打一行「面板启动」，包含屏幕名、刘海矩形、顶部留白、展开尺寸与 **level 数值**——
**排查任何「面板看不见」的问题，第一件事就是看这行的 level 是不是 1000。**

### 14.3 三个可观测入口

1. **调试面板**（菜单栏图标 → 调试面板）：实时显示所有屏幕的完整几何 + 面板状态、
   窗口 frame、层级、挂起原因、热区矩形、鼠标位置、悬停状态机内部状态。每秒刷新。
2. **菜单栏 → 展开 / 收起面板**：不依赖鼠标悬停，手动触发动画，用来单独验证几何与动画。
3. **日志**：唯一能回答「为什么不展开」「为什么被挂起」的手段。

### 14.4 典型故障速查

| 现象 | 先看什么 | 最可能的原因 |
|---|---|---|
| 面板完全看不见 | 启动日志的 `level=` | 不是 1000（被 `isFloatingPanel` 覆盖、或守卫降级中） |
| 鼠标划到刘海没反应 | 日志里 `expand 被拒绝:` | 处于 `suspended`（全屏 / 系统弹窗）或已是展开态 |
| 展开了但收不回去 | 调试面板的「悬停状态」「热区」 | 热区矩形算错；或全局 mouseMoved 丢事件（安全网应兜住） |
| 悬停偶尔失灵 | 调试面板的「鼠标位置」vs「热区」 | 屏幕缩放/分辨率变化后几何未重算 |
| 其他 App 全屏时还弹出来 | 日志 `检测到其他 App 全屏` | `LayerGuard.isFullScreenWindowActive` 启发式没命中（需换私有 API，见 Q7） |
| 授权对话框点不到 | 日志 `检测到系统模态弹窗` | `systemModalOwners` 名单没覆盖到该进程名，需补进 `LayerGuard` |
| 每次重建都要重新授权 | `security find-identity -v -p codesigning` | 用的 ad-hoc 签名，先跑 `./scripts/setup-signing.sh` |
| 开关是开的但仍报未授权 | 日志里 `权限未齐` 的那行 | TCC 记录与签名失配 → `./scripts/reset-permissions.sh`（详见 §14.7） |
| 申请授权但不弹系统提示 | — | 辅助功能提示每次启动只弹一次且拒绝后不再弹，只能走「打开系统设置」 |
| 改了代码但没生效 | `pgrep -x NotchSwitch` | 旧实例没杀掉，`open` 只激活了旧实例 → 用 `./scripts/run-app.sh` |

### 14.5 单元测试

```bash
swift test                                        # 全部
swift test --filter NotchGeometryTests             # 只跑几何
swift test --filter testNotchedDisplayMatchesMeasuredNotchFrame
```

几何测试用的是**本机实测数据**，所以它同时也在守住「不可硬编码刘海尺寸」这条约束。
换机器或改缩放模式后，如果这些断言失败，说明代码里混进了硬编码。

### 14.6 改代码后要跑什么

```bash
swift build && swift test && ./scripts/build-app.sh && open build/NotchSwitch.app
```

前两步能拦住绝大多数回归；第三步之后需要人工看的是**层级、动画、悬停手感**这三类，
它们没有自动化手段（这也是 §13.3 那几项一直挂着的原因）。

推荐直接用 `scripts/run-app.sh`（它会先 kill 旧实例再 open，见 §14.7 第 3 条）。

### 14.7 权限授权排查（授权失败 / 一直显示未授权）

按顺序排查，多数问题在第 2、3 条。

**1. 先确认真实的权限状态**

```bash
pkill -x NotchSwitch
/Users/lionaillen/Documents/daily/change/scripts/run-app.sh
/usr/bin/log show --last 30s --info --predicate 'subsystem == "com.notchswitch.app"' | grep 权限未齐
```

日志里的 `辅助功能=? 屏幕录制=?` 才是真实状态。

> **不要从终端直接执行 `Contents/MacOS/NotchSwitch` 来判断权限。**
> 实测对比：同一个构建，终端直跑报 `辅助功能=true`，经 `open` 启动报 `辅助功能=false`。
> 原因是 TCC 把权限归因到**责任进程**，终端启动时会继承终端自身的授权。
> 这会把「其实没授权」误判成「已授权」，是排查中最容易走错的一步。

**2. 用户点了「申请授权」但系统不弹窗**

辅助功能的系统提示**每次启动只弹一次**，且被拒绝过之后就不再弹。
此时唯一路径是「打开系统设置」按钮 → 在列表里找到 NotchSwitch → 打开开关。
如果列表里**找不到 NotchSwitch**，说明系统还没登记它，先做第 3 步再重试。

**3. 开关是开的，但仍显示未授权（最常见）**

原因：TCC 把授权与**代码签名身份**绑定。用 ad-hoc 签名时，每次 `build-app.sh`
身份都会变，于是系统里残留一条对不上号的旧记录 —— 开关显示「开」，但
`AXIsProcessTrusted()` 返回 `false`，而且再也不会弹授权提示。**只能重置记录解决**：

```bash
./scripts/reset-permissions.sh        # 清掉本 App 的 TCC 记录
./scripts/setup-signing.sh            # 建立固定签名身份（根治）
./scripts/run-app.sh                  # 重建并重启
```

然后重新授权。固定签名身份建好之后，这个问题不会再出现。

**4. App 每次都启动但权限一直拿不到 / `open` 没反应**

`Info.plist` 里有 `LSMultipleInstancesProhibited=true`（菜单栏应用不允许跑两份）。
后果是**旧实例还活着时 `open` 只会激活旧实例，不会启动新构建**，
表现成「改了代码但没生效」或「一直在用旧版本」。所以要先 kill：

```bash
pkill -x NotchSwitch && ./scripts/run-app.sh
```

`run-app.sh` 已经把这一步做进去了。

**5. 运行位置不理想**

TCC 记录与路径相关。放在 `~/Documents/...` 下虽然能用，但推荐把
`build/NotchSwitch.app` 拖到「应用程序」文件夹：系统设置里更容易找到，
也不容易因重新构建而失配。引导窗口在检测到不在「应用程序」下时会给出提示。

**6. 授权后部分功能仍不生效**

运行中的进程 AX 信任状态可能是陈旧的，**重启一次即可**。
引导窗口右下角和菜单栏都有「重启 NotchSwitch」。

### 14.8 签名与 TCC 稳定性（最关键的一节）

**一切授权问题的根源都在这里。** 如果签名不稳定，后面所有排查都是白费。

**怎么判断签名是否稳定**——只看一行：

```bash
codesign -d -r- /Applications/NotchSwitch.app 2>&1 | grep designated
```

| 输出 | 含义 |
|---|---|
| `designated => cdhash H"a1b2..."` | **ad-hoc 签名，不稳定**。cdhash 每次构建都变 → TCC 记录必然失配 |
| `designated => identifier "com.notchswitch.app" and certificate leaf = H"7148..."` | **证书制，稳定**。重建后 DR 不变 → 授权可长期有效 |

**修复（一次性）**：

```bash
./scripts/setup-signing.sh          # 建立固定签名身份（独立钥匙串，无需交互）
./scripts/reset-permissions.sh      # 清掉 ad-hoc 留下的失效 TCC 记录
./scripts/run-app.sh --install      # 重新签名构建 → 安装到 /Applications → 启动
```

**搭建这套签名链路时踩过的 5 个坑**（脚本已全部处理，改脚本时别踩回去）：

| # | 坑 | 症状 | 解法 |
|---|---|---|---|
| 1 | OpenSSL 3.x 导出的 p12 macOS 不认 | `SecKeychainItemImport: MAC verification failed during PKCS12 import` | 不用 p12，**分别导入 PEM** 私钥与证书 |
| 2 | 缺 key partition 设置 | `codesign: errSecInternalComponent`（拿不到私钥） | `security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k <pwd> <keychain>` |
| 3 | 用 `find-identity -v` 判断身份 | 明明建好了却「未找到签名身份」 | `-v` 只列 trusted 身份；自签名会显示 `CSSMERR_TP_NOT_TRUSTED` 而被过滤。**去掉 `-v`** |
| 4 | 想做 `add-trusted-cert` | 弹 GUI 密码框、脚本卡死 | **不需要**。签名只需私钥+证书；信任只影响 Gatekeeper，本地构建的 App 无 quarantine 标记 |
| 5 | 同一 bundle id 有两份副本 | `open /Applications/...` 实际跑起来的是 `build/` 那份 | 只保留一个位置，`run-app.sh --install` 会删掉 `build/` 副本 |

**一条铁律：只从一个位置运行。**
`build/` 和 `/Applications/` 各有一份时，TCC 会记录两套授权，而你永远搞不清点开的是哪一份。
统一用 `./scripts/run-app.sh --install`。
