# NotchSwitch

**把 MacBook 的刘海，变成你手上最快的窗口切换器。**

[![macOS](https://img.shields.io/badge/macOS-14%2B-black?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?logo=swift&logoColor=white)](https://swift.org)
[![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-required-silver?logo=apple&logoColor=white)](#系统要求)
[![License](https://img.shields.io/badge/license-MIT-blue)](./LICENSE)

```
   鼠标移到刘海   →   长出一条窗口预览带   →   滚轮前后翻   →   点击切过去
```

---

## 你有没有过这种时刻

- 开了十几个窗口，`⌘Tab` 只能在**应用**之间跳，切过去还得再找一遍窗口
- 调度中心一按，满屏缩略图，眼睛要重新搜一遍才知道哪个是哪个
- Dock 上同一个应用的图标点开，弹出菜单写着「窗口 1、窗口 2」——**完全不知道谁是谁**

Dock 管应用，`⌘Tab` 管应用，调度中心管全部但太吵。

**没有一个东西管「我现在想切到那个窗口」。**

NotchSwitch 就是干这个的：**一眼看到窗口里是什么，一次点击切过去。**

---

## 三十秒上手

```bash
git clone https://github.com/seesawz/notch-switch.git
cd notch-switch

./scripts/setup-signing.sh      # 只做一次，别跳过
./scripts/run-app.sh --install  # 构建 → 安装 → 启动
```

首次启动会弹出权限引导，按提示点两下就完事。

| 操作 | 结果 |
|---|---|
| 鼠标移到刘海 | 预览带滑出来 |
| 鼠标移开 | 自动收起 |
| 滚轮 / 触控板双指滑动 | 前后翻窗口 |
| 点一下卡片 | 切过去 |

> **别跳过第一步。** macOS 的权限是和「应用签名」绑定的。用临时签名的话，每次重新构建系统都会当成一个全新 App——设置里的开关明明是开的，程序却以为没授权，而且**再也不会弹授权提示**。固定签名身份可以一次性根治。
>
> 已经踩坑了？`./scripts/reset-permissions.sh` 清理一下再来。

---

## 它做对的几件事

**刘海即入口**
不占 Dock，不占菜单栏，不进 `⌘Tab`。收起时完全不可见——你甚至不会意识到它在那儿。

**真的看得到内容**
不是应用图标，是 ScreenCaptureKit 抓的**实时窗口画面**。

**顺序永远是对的**
按「最近用过」排，不是按打开顺序。你一切窗口，列表立刻重排——靠系统事件驱动，不轮询、不烧电。

**该消失时消失**
其他 App 进入全屏时自动隐藏，退出后自动恢复。看片、游戏、演示的时候它绝不打扰你。

**权限缺了也照样能用**
没有屏幕录制权限 → 退化成应用图标；没有辅助功能权限 → 面板里直接写清楚该怎么办。

**多显示器也不犯迷糊**
自动认准带刘海的那块内建屏。外接屏、无刘海机型都有自己的退化方案，不会崩、不会错位。

---

## 说点诚实的

这是个**早期项目**，现在能用，但还差几块：

- **没有悬停大预览图** —— 这是下一步要做的核心功能
- **没有搜索** —— 窗口多了之后需要，正在做
- **没有设置页** —— 参数都写在代码里（唯一的例外：无刘海屏幕可在菜单栏里关掉「顶部触发」开关）

还有几个是**设计取舍，不是 bug**：

- 其他 App 全屏时它会隐藏。这是故意的
- 跨 Space 的窗口点击后会切过去，做不到凭空激活（系统限制）
- 最小化的窗口截不到图，会退化成应用图标
- 不会上架 Mac App Store —— 用到了系统私有 API

---

## 系统要求

| | |
|---|---|
| macOS | 14 (Sonoma) 或更高 |
| 芯片 | Apple Silicon（Intel 未测试） |
| 权限 | 辅助功能 + 屏幕录制 |

<details>
<summary><b>为什么需要这两个权限？</b></summary>

**辅助功能** —— 读取窗口列表、记录你最近用过的顺序、把窗口切到前台。缺了它核心功能不可用。

**屏幕录制** —— 抓窗口画面和标题。缺了它缩略图会退化成应用图标，其余功能照常。

两项权限都只在本地使用，NotchSwitch **不联网、不上传任何数据、没有遥测**。

</details>

---

## 对开发者

Swift 6 + SwiftPM。核心逻辑与 UI 分离，`NotchKit` 可以单独跑测试。

```bash
swift build                     # 编译
swift test                      # 34 项单元测试
./scripts/run-app.sh --install  # 构建 + 安装 + 启动
xed .                           # 用 Xcode 打开（可断点调试）
```

看日志：

```bash
/usr/bin/log stream --predicate 'subsystem == "com.notchswitch.app"'
```

> zsh 里 `log` 是内建命令，**必须写全路径 `/usr/bin/log`**。

调试时还有菜单栏里的「调试面板…」，实时显示屏幕几何、面板层级、热区、窗口列表和缩略图缓存。

```
Sources/
├── NotchKit/         核心逻辑（纯 AppKit，可单测）
│   ├── 刘海几何 / 面板 / 层级守卫 / 悬停监听
│   ├── WindowKit/    窗口枚举 / MRU 排序 / 缩略图 / 窗口激活
│   └── PrivateAPI/   私有符号动态查找 + 能力检测（符号没了就降级，不崩）
└── NotchSwitch/      应用外壳（入口 / 菜单栏 / SwiftUI 视图）
```

### 设计与决策

想看「为什么这么做」，全部在 **[PLAN.md](./PLAN.md)**：技术可行性逐项分析、风险登记表、决策记录（ADR）、调试手册，以及一份相当完整的踩坑记录。

如果要动签名或权限相关的代码，**先读 §14.8「签名与 TCC 稳定性」**——那里面的 5 个坑每一个都会让人浪费半天。

---

## 路线图

- [x] 刘海贴片 + 悬停展开收起
- [x] 窗口枚举 + 最近使用排序 + 点击切换
- [x] 实时缩略图
- [x] 滚轮连续滚动
- [ ] **悬停大预览图** ← 下一步
- [ ] 键入搜索（含拼音 / 首字母 / 模糊匹配）
- [ ] 设置页
- [ ] 跨 Space 激活的完整策略
- [ ] 签名公证 + 自动更新

---

## 致谢

刘海几何算法参考了 [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit)（MIT）。
窗口枚举与 MRU 的架构思路参考了 [alt-tab](https://github.com/kaikozlov/alt-tab)。

## 许可

[MIT](./LICENSE) © 2026 seesawz
