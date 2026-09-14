# NotchSwitch

把 MacBook 的刘海变成一个「前台调度」式的横向窗口切换条。

鼠标移到刘海 → 向下长出一条横向预览带（可视 4 张，实时窗口缩略图）→ 滚轮前后翻 → 点击即切到那个窗口。整个过程中前台 App 不会被打断。

```
        ╭──────────╮
      ╭─┴──────────┴──────────────────────────────╮
      │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────── │
      │  │ 窗口1  │ │ 窗口2  │ │ 窗口3  │ │ 窗口4 │
      │  └────────┘ └────────┘ └────────┘ └────── │
      ╰───────────────────────────────────────────╯
         鼠标移到刘海 → 展开    滚轮 → 前后翻    点击 → 切换
```

## 特性

- **刘海即入口**：不占 Dock、不占菜单栏、不进 ⌘Tab，收起时完全不可见
- **实时窗口缩略图**：ScreenCaptureKit 抓的真实画面，不是应用图标
- **最近使用顺序**：MRU 由 AX 事件驱动维护，空闲时零轮询、零 CPU
- **常驻最前台**：面板层级压制所有普通窗口与系统通知；**唯一例外是其他 App 全屏时**（这是有意为之）
- **连续滚动**：滚轮 / 触控板双指滑动跟手滚动，松手吸附对齐
- **优雅降级**：缺屏幕录制权限时退化为应用图标，缺辅助功能权限时面板内直接说明
- **多显示器 / 无刘海机型**：自动挑带刘海的内建屏，无刘海时退化为菜单栏中央热区

## 系统要求

| 项 | 要求 |
|---|---|
| 系统 | macOS 14 或更高 |
| 芯片 | Apple Silicon（Intel 未测试） |
| 权限 | **辅助功能** + **屏幕录制**（缺任一项都会降级） |

## 快速开始

```bash
git clone https://github.com/seesawz/notch-switch.git
cd notch-switch

# 1. 建立本机固定签名身份（只做一次，必做）
./scripts/setup-signing.sh

# 2. 构建 + 安装到 /Applications + 启动
./scripts/run-app.sh --install
```

首次启动会自动打开权限引导窗口，按提示授予两项权限即可。

> **为什么第一步不能省**：macOS 的 TCC 权限与**代码签名身份**绑定。
> 用 ad-hoc 签名时，每次重新构建签名都会变，系统会认为这是一个「新 App」：
> 系统设置里的开关看起来是开着的，但程序检测到的仍是「未授权」，而且不再弹授权提示——
> 授权路径会被彻底堵死。固定签名身份可以根治这个问题。

## 使用

| 操作 | 行为 |
|---|---|
| 鼠标移到刘海 | 展开预览带 |
| 鼠标移开 | 240ms 后自动收起 |
| 滚轮 / 触控板双指滑动 | 前后翻窗口（不需要按 Shift） |
| 点击卡片 | 把该窗口切到前台并聚焦 |
| 其他 App 全屏 | 面板自动隐藏，退出全屏后自动恢复 |

菜单栏图标（⚠ 表示权限未齐）里还有：展开/收起面板、调试面板、权限引导、重启、在访达中显示。

## 权限

| 权限 | 用途 | 缺失时的降级 |
|---|---|---|
| 辅助功能 | 枚举窗口、维护最近使用顺序、把窗口切到前台 | **核心功能不可用** |
| 屏幕录制 | 捕获窗口缩略图与标题 | 缩略图退化为应用图标 |

授权后如仍显示未授权，通常是签名变了导致记录失配，用这条命令重置：

```bash
./scripts/reset-permissions.sh
```

## 已知限制

- **不上架 Mac App Store**：依赖无障碍/屏幕录制权限，且使用了私有 API
- **未实现**：悬停大预览图、键入搜索、拼音匹配 —— 见路线图
- **其他 App 全屏时不可见**：这是需求规定的行为，不是 bug
- **跨 Space 的窗口**：点击会切换 Space，无法在当前 Space 直接激活
- **最小化窗口**：无法用 ScreenCaptureKit 截图，降级为应用图标
- **与其他刘海应用共存**：不做互斥，层级可能互相覆盖

## 开发

### 常用命令

```bash
swift build                     # 编译
swift test                      # 单元测试（31 项）
./scripts/run-app.sh            # 从 build/ 启动
./scripts/run-app.sh --install  # 装到 /Applications 再启动（推荐）
./scripts/build-app.sh debug    # 只构建，不启动
xed .                           # 用 Xcode 打开（可打断点）
```

### 调试

日志用 `os.Logger`，运行中也能直接 stream：

```bash
# 重要事件：展开/收起/层级变化/窗口枚举
/usr/bin/log stream --predicate 'subsystem == "com.notchswitch.app"'

# 含悬停等高频细节
/usr/bin/log stream --debug --predicate 'subsystem == "com.notchswitch.app"'
```

> zsh 里 `log` 是内建命令，**必须写全路径 `/usr/bin/log`**。

菜单栏 →「调试面板…」可以实时看到屏幕几何、面板状态、热区、窗口列表与缩略图缓存情况。

> ⚠️ 不要用 `swift run` 或直接执行 `Contents/MacOS/NotchSwitch` 来验证权限：
> 那种启动方式会**继承终端进程的 TCC 归因**，把「其实没授权」误报成「已授权」。
> 实测同一份构建：终端直跑报 `辅助功能=true`，经 `open` 启动报 `false`。

### 项目结构

```
Package.swift                    SwiftPM 包（替代 .xcodeproj）
Sources/
├── NotchKit/                    核心逻辑（纯 AppKit，可单测）
│   ├── NotchGeometry             刘海几何（纯函数）
│   ├── NotchPanel                NSPanel 子类（层级 / 跨 Space）
│   ├── NotchContentContainer     固定尺寸内容裁剪 + 滚动事件捕获
│   ├── NotchPanelController      展开收起 / 悬停 / 屏幕变化 总控
│   ├── LayerGuard                常驻最前台维护（全屏检测、临时降级）
│   ├── HoverMonitor              全局 mouseMoved 热区判定
│   ├── ScrollFollow              滚动跟随 + 吸附（纯逻辑）
│   ├── ScrollDelta               滚动输入归一化（纯逻辑）
│   ├── PanelSelection            预览带水平位移（帧驱动）
│   ├── WindowKit/                窗口枚举 / MRU / 缩略图 / 激活
│   └── PrivateAPI/               dlsym 动态查找私有符号 + 能力检测
└── NotchSwitch/                应用外壳（入口 / 菜单栏 / SwiftUI 视图）
scripts/                        签名、构建、运行、权限重置
Tests/NotchKitTests/            31 项单元测试
```

## 路线图

- [x] 刘海贴片 + 悬停展开收起
- [x] 窗口枚举 + MRU 排序 + 点击切换
- [x] 实时缩略图（ScreenCaptureKit + LRU 缓存）
- [x] 滚轮连续滚动
- [ ] **悬停大预览图** ← 核心差异点，下一步
- [ ] 键入搜索（含拼音 / 首字母 / 模糊匹配）
- [ ] 设置页
- [ ] 跨 Space 激活的完整策略
- [ ] Developer ID 签名 + 公证 + Sparkle 自动更新

## 文档

设计与决策记录全部在 [`PLAN.md`](./PLAN.md)，包括：技术可行性逐项分析、风险登记表、
决策记录（ADR）、调试手册、踩坑记录。开发前建议先读 §14.8「签名与 TCC 稳定性」。

## 致谢

刘海几何算法参考了 [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)（MIT）。
窗口枚举与 MRU 的架构思路参考了 [alt-tab](https://github.com/kaikozlov/alt-tab)。

## 许可

[MIT](./LICENSE) © 2026 seesawz
