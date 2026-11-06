# UI / 交互评审：实现与「LingoLens macOS 原型」的差距清单

- 日期：2026-11-06
- 对照对象：`~/Downloads/LingoLens macOS 原型`（Figma Make 高保真原型：流程总览 / 首次启动 / 菜单栏 / 主窗口 4 页 / 划词翻译 / 实时字幕 / 全局错误 / 组件库）
- 评审方式：原型逐屏运行截图 + 本仓库 SwiftUI 代码走查 + 运行态 Accessibility 树核对（未做像素级截图对比）
- 结论：**主干功能与三个浮窗基本对齐原型；未落地的集中在「首次启动引导」「全局反馈/错误体系」「会议详情的信息架构」「菜单栏运行态可视化」四处。**

## 本轮已落地（2026-11-06）

| 项 | 改动 |
|---|---|
| P0-4 会议详情左右分栏 | `App/MeetingsView.swift`：`VSplitView` 换成转写 / 可拖拽分隔条 / 纪要的 `HStack`；比例存 `@AppStorage("meetings.splitRatio")`，默认 0.53，拖动按像素 1:1 跟手，受两侧最小宽度（220 / 280）约束；纪要工具条拆成两行（模板、输出语言）以适配较窄的右栏；默认窗口放大到 1120×700 与原型同量级（`MainWindowController`、`LingoLensApp`）。 |
| P0-2 会话结束回执 | 新增 `App/ToastView.swift`；`AudioSessionController.stop()` 返回刚结束的会议，`AppEnvironment.stopAudioSession()` 弹「会议已保存」toast（主窗口底部 + 菜单栏面板顶部，6 秒自动消失，可「查看会议」跳转）。 |
| P1-6/7 菜单栏运行态 | `AudioBufferTools.level(of:)` 计算 RMS 电平（-60 dB→0），`AudioSessionController` 以 15 Hz 平滑发布 `levels`；菜单栏面板显示「对方 / 我」两路分段电平（颜色沿用说话人配色），并在字幕浮窗显示时提供「查看浮窗」入口。 |
| P0-1 首次启动引导 | 新增 `App/OnboardingView.swift`：左侧步骤轨 + 5 步（欢迎 / 运行环境进度 / 选择模型 / 授权 / 试一试 ⌥D）；运行环境进度、模型列表、权限面板全部复用现有状态；完成后写 `LingoLens.didFinishOnboarding`，设置页「帮助 → 重新查看」可再次打开。 |
| 附：退出竞态 | `ServerPool.shutdown()` 之前只停已登记进程，启动中的 `ensure` 可能在关机后拉起新进程（实测会残留 `mlx_vlm.server`）。现在关机置位后拒绝新启动，并在拉起前检查取消；新增 2 个回归测试（关机后 ensure 抛错、启动中关机进程被终止）。 |
| P1-1 会议列表 | `MeetingSummary` 增加 `preview`（只读转写文件前 8 KB 取首条），列表显示「今天/昨天 HH:mm · 时长」与预览句；右键增加「在 Finder 中显示」。 |
| P1-2 详情信息架构 | 标题右侧加「更多」菜单（复制转写 / 导出纪要 / 在 Finder 中显示 / 删除会议，删除带确认）；新增「转写与纪要 / 会议信息」分段，会议信息页展示起止时间、时长、句数、语言、纪要字数与存储路径。 |
| P1-3 纪要定位 | 纪要每行若包含时间标记，行尾渲染「定位 hh:mm:ss」，点击用 `scrollPosition(id:anchor: .center)` 滚到对应转写并高亮 2 秒；`mm:ss` 按距会议开始的偏移匹配。 |
| P1-4 搜索命中 | 转写搜索显示「N 条命中」；命中行切成只读文本、命中处黄色高亮加粗，清空搜索恢复可编辑。 |
| P1-5 生成进度 | 生成时解析「第 x/y 段」显示确定进度条 + 已生成字数；中途停止会把已产出内容落盘并提示字数。 |

| P1-8 模型页 | 新增 `ModelDownloadState`（页内卡片与下载面板共用）：页内显示仓库名、第 i/n 个文件、已下载/总量、速度、剩余时间、百分比、暂停/继续/取消；关闭面板不再中断下载。列表标题改为「已安装 N · 占用 X GB」。 |
| P1-9 设置二级导航 | 顶部 6 段 segmented 换成设置内的左侧列表（通用 / 音频与字幕 / 场景 / 纪要模板 / 模型服务 / 权限与运行时）。 |
| P1-10 纪要模板分区 | 设置新增「纪要模板」页：列出模板与提示词摘要，内置模板带「内置」标签，可打开模板编辑器。 |
| P1-11 Dock 显示 | 设置 → 通用新增「在 Dock 中显示」，切换即时生效（`setActivationPolicy`），启动时按保存值应用。 |
| P1-12 首页 | 标题改为按时段的问候（早上好/上午好/…），最近会议加日期块，运行时卡片新增「系统语音识别 · 支持 N 种语言」（`SpeechAssetManager`）。 |
| P0-3 错误体系 | `lastError: String?` 换成结构化 `AppError`（标题 / 说明 / 错误码 / 恢复动作）。主窗口顶部改为可承载多个动作的 `ProblemBanner`（替掉「出错了 / 好」alert），菜单栏面板也有错误行。各调用点补上语义标题与错误码（`RUNTIME_INSTALL`、`MODEL_IMPORT`、`SERVER_START`、`CLIPBOARD_EMPTY` 等）和恢复动作（查看日志 / 重试 / 手动输入）。 |

### P2 打磨项（同批完成）

| 项 | 改动 |
|---|---|
| 空态去重 | 会议页空数据时侧栏只留一行「暂无会议」，右侧详情承担完整引导 + 「开始音频会话」按钮。 |
| 时间口径 | 转写行改为距会议开始的 `mm:ss`；纪要里的定位按钮同步换算成 `mm:ss`，两处读数一致。 |
| 侧边栏 | 顶部加品牌区（L + LingoLens）；有新会议且没打开会议页时「会议」项显示小圆点，进入会议页自动清除。 |
| 字幕浮窗位置 | 拖动/缩放后写入 `UserDefaults`，下次启动恢复到上次位置；保存的位置不在任何屏幕上时回退到底部默认位置。 |
| 主窗口统一 | 删除 SwiftUI `Window` 场景，主窗口只由 `MainWindowController` 创建，消除两套窗口生命周期（标题/尺寸/关闭行为）不一致。 |
| 颜色 token | Assets 新增 `Success` / `Warning` / `Danger`（含深色变体），App 内散落的 `.green/.orange/.red` 全部换成 `Color.success/.warning/.danger`。 |
| 减少动态效果 | 主窗口 toast/错误条与字幕浮窗的动画在 `accessibilityReduceMotion` 下关闭。 |
| 快捷键 | ⌘1–⌘4 切页、⌘, 打开设置、⌘W 关闭主窗口（本地事件监听，中文输入法下按物理键兜底）；Esc 关闭同时实现了 monitor 与 `cancelOperation`/`keyDown` 两条路径，但合成按键事件始终被前台的其他应用吃掉，未能实机验证。 |

> 顺带修掉一个定位相关的隐藏 bug：`MeetingsView.timeString` 是 `HH:mm`，用它跟 `hh:mm:ss` 标记比对永远不相等，导致定位一律跳到会议末尾。新增 `clockString`（HH:mm:ss）用于精确匹配。

---

## 0. 已经做好的部分（不要推翻）

| 模块 | 现状 | 评价 |
|---|---|---|
| 划词翻译浮窗 | 420×280 浮窗、pin、流式光标、首字/tok/s、⌘↩ 重译、⇧⌘C 复制、Esc 关闭、失焦自动收起、贴鼠标定位并夹在屏幕内 | 与原型 D 帧几乎 1:1，交互完整 |
| 实时字幕浮窗 | 说话人胶囊 + 原文小字 + 译文大字、未定稿灰显 + 省略号动画、悬停控制条（暂停/字号/透明度/穿透/关闭）、点击穿透 | 与原型 E 帧对齐，细节甚至更多 |
| 模型页 | 内存分级（可用/偏紧/不足）、来源标签、服务进程/重启计数、失败信息内联 | 比原型的信息密度更合理 |
| 会议页功能 | 逐条编辑转写、Markdown 预览（标题/列表/任务/表格）、模板增删改、流式生成、停止、导出 .md | 功能齐，问题在版式（见 P0-4） |
| 首页问题横幅 | 运行时失败 / 常驻模型失败 / 无模型 / 辅助功能未授权 / 热键冲突，均带动作按钮 | 危机沟通的方向是对的 |

---

## 1. P0：原型里有、实现完全缺失（影响首次体验与主流程闭环）

### P0-1 首次启动引导整块没做（原型「首次启动」B 帧）

- 现状：`App/AppDelegate.swift:5-21` 只在首次启动时 **直接弹出主窗口**（`UserDefaults "LingoLens.didOpenMainWindow"`），没有引导。
- 原型：5 步左侧步骤轨 + 内容区 —— 欢迎 → 运行环境（安装进度）→ 选择模型（推荐模型 / 扫描本地）→ 权限清单（辅助功能 / 麦克风 / 系统音频）→ 试一试 ⌥D，每步一个主按钮，进度未完成时禁用「继续」。
- 影响：新用户第一次打开看到的是「还没有模型 + 三条黄色告警」，不知道该先做什么；`installRuntime`、`refreshModels` 都在后台悄悄跑，用户看不到进度。
- 建议落点：新建 `App/OnboardingView.swift`，用 `@AppStorage("didFinishOnboarding")` 控制；把 AppDelegate 的首次启动分支改成先开引导窗口。步骤内的进度/权限可直接复用 `environment.runtimeProgress`、`PermissionsSettingsView`、`AccessibilityPermission`。

### P0-2 音频会话结束后没有任何反馈（原型 A 帧的 toast）

- 现状：`AudioSessionController.stop()` → `onSessionFinished` → `AppEnvironment.meetingsRevision += 1`，仅此。用户按「停止」后界面没有任何「已保存/去查看」的闭环，容易以为没存上。
- 原型：停止后弹 toast「会议已保存 / 转写已保存在“会议”中」，带「查看会议」按钮。
- 建议：`AppEnvironment.stopAudioSession()` 结束时若 `isRecordingMeeting` 为真，设置一个 `@Published var toast: Toast?`，主窗口与菜单栏面板共用一个轻量 overlay；点击跳到 `.meetings` + `focusMeetingID`。系统通知（`UNUserNotificationCenter`）可作为二选一或补充。

### P0-3 错误体系退化成“一个弹窗一句好”（原型 F 帧）

- 现状：所有错误汇聚成 `AppEnvironment.lastError: String?`，主窗口只有一个 `.alert("出错了") { Button("好") }`（`App/MainWindowView.swift:31-42`），浮窗/菜单栏里发生的错误甚至可能完全不可见。
- 原型：4 类错误（模型启动失败 / 内存不足 / 权限被拒 / 运行时安装失败），每类都有 **两条不同性质的动作**（查看日志 + 重试、换小模型 + 释放内存后重试、去授权 + 稍后）、错误码、以及「本地数据未受影响」的说明。
- 影响：首页已有 `IssueBanner` 体系，但会话/翻译/纪要路径上的错误走的是 alert，两套体系并存且互相重复（模型失败时首页 banner 和 alert 同时出现）。
- 建议：把 `lastError: String? ` 升级为 `AppError { title, message, code, actions: [(String, () -> Void)] }`；主窗口用一个「问题中心」区域（首页 banner 列表即可）替代 alert；浮窗内部用内联错误卡（翻译浮窗已经这么做了，保持并统一文案）。

### P0-4 会议详情版式与原型相反：上下分栏 vs 左右分栏

- 现状：`App/MeetingsView.swift:134-141` 用 `VSplitView`（转写在上、纪要在下），且 `minHeight 160/220`。主窗口最小 940×600 时，两块都被压得很扁，纪要基本要一直滚。
- 原型：左转写 / 中 6px 可拖拽分隔条 / 右纪要，分隔条可调 38%–68%，宽度利用充分（阅读转写和对照纪要可同时进行）。
- 影响：这是会议页最主要的可用性问题，且宽屏下浪费了水平空间。
- 建议：改回 `HSplitView`（或自绘 `NSSplitView` 以支持高度记忆），分隔比例存进 `AppSettings`。注意仓库里曾有「HSplitView 撑开侧边栏」的教训（`MeetingsView.swift:28-29` 的注释），实现时给两侧 `.frame(minWidth:maxWidth: .infinity)` 并固定外层宽度。

---

## 2. P1：原型有、实现里只做了一半 / 明显弱化

| # | 原型点 | 现状 | 差距 |
|---|---|---|---|
| P1-1 | 会议列表行：标题 + 「纪要」标签 + 相对时间 + **转写预览一句** | `MeetingsView.swift:97-125` 只有标题、纪要标签、绝对时间 + 时长 | 没有预览句，列表扫读性差；时间是 `dateString`（medium + short），不是「今天 10:08」式相对时间 |
| P1-2 | 详情头部「更多」菜单 + 「转写与纪要 / 会议信息」tab | 只有可编辑标题 + 一行元信息 | 没有会议信息面板（语言、来源、条目数以外的信息）、没有删除/导出转写的入口聚合（删除藏在列表右键菜单） |
| P1-3 | 纪要行动项可「定位 00:48」并高亮对应转写行 | 纪要只是 Markdown 预览，任务项是静态勾选框图标 | 缺少「纪要 ↔ 转写」双向定位，这是原型里最有产品感的一处 |
| P1-4 | 转写搜索有命中跳转/高亮 | `filteredEntries` 只做过滤 | 长会议里过滤后上下文丢失，没有命中高亮与「第 n/m 条」 |
| P1-5 | 纪要生成中：阶段环 1/3 + 阶段轨 + 停止 | 小 spinner + 一行 `phaseText` | 缺少可预期的进度表达；停止后已生成内容未写入存储（`generate` 的 CancellationError 分支只改状态） |
| P1-6 | 菜单栏运行态：**对方/我 两路音频电平条** | `MenuBarView.swift:95-151` 只有计时 + 一行状态 | 用户无法判断「到底有没有采到声音」，这是会话中最需要的反馈 |
| P1-7 | 菜单栏「字幕浮窗正在显示 → 查看浮窗」 | 只有一个 `显示字幕浮窗` 开关 | 没有「跳过去看一眼」的入口；穿透开关在浮窗显示时才出现，位置也偏隐蔽 |
| P1-8 | 模型页：页内下载卡（速度/剩余时间/暂停继续/取消）+ 表格列头 + 「已安装 N 个 · 占用 X GB」 | 下载是一个 sheet（`ModelsView.swift:31-34`），关掉就看不到进度；列表是行卡片，无列对齐；无汇总行 | 长下载（数 GB）期间用户看不到页面内进度；模型多了以后没有「占用总空间」概念 |
| P1-9 | 设置：左侧二级分区 + 每行说明文字 | `SettingsView.swift:26-32` 顶部 5 段 segmented control；说明写在 Section footer | 窄窗口 5 段会挤；每行缺少 hint（尤其「场景」「服务参数」这类术语多的区域） |
| P1-10 | 设置里有「纪要模板」分区 | 模板管理是会议页的 `MinutesTemplateSheet` | 入口位置偏、可发现性差；原型把它当设置项更合理 |
| P1-11 | 设置「在 Dock 中显示」 | 无（应用固定 `.accessory`） | 属于可选能力，但原型明确列出，且实现成本低（切换 activationPolicy） |
| P1-12 | 首页：时间问候「上午好」+ 日期块最近会议 + 运行时两行（MLX / 系统语音识别） | 标题是「LingoLens」；最近会议无日期块；运行时卡只有 mlx-vlm + 服务数（`HomeView.swift:40-52, 155-186`） | 首页少了「今天」的临场感；系统语音识别的可用语言状态没暴露，出问题时用户不知道去哪看 |

---

## 3. P2：细节与打磨

1. **侧边栏品牌区与新增会议小圆点**：原型 sidebar 顶部有 logo + 产品名，会议项在有待看内容时显示小圆点；实现是纯系统 `List`（`MainWindowView.swift:33-42`），没有品牌区，也没有「新会议」提示。
2. **窗口标题**：实测运行中的窗口标题是「会议」（跟随 `.navigationTitle(environment.mainTab.title)`），原型固定为「LingoLens」。
3. **两套主窗口创建路径**：`LingoLensApp.swift:17-22` 声明了 `Window("LingoLens", id: "main")`，同时 `MainWindowController` 又自建 `NSWindow`，菜单栏「打开主窗口」走后者。两者尺寸/最小尺寸/标题/关闭行为都不完全一致，容易复现「点了打开但焦点跑到另一个窗口」。建议只保留一套。
4. **会议页空态三重奏**：空数据时侧栏 `ContentUnavailableView`（标题+说明）、详情区又一句「选择一场会议 / 左侧选择会议查看转写与纪要」、侧栏说明再重复一次，一屏三条空态文案（运行态 AX 树可直接看到）。原型只有列表空态 + 详情静默。
5. **时间格式**：转写行是 `HH:mm:ss`（`MeetingsView.swift:507-511`），原型是 `mm:ss`；会议列表也是绝对日期，缺「今天/昨天」。
6. **动效规范只落地了一部分**：浮窗 150ms ease-out、字幕行 240ms 曲线都有；页面切换、会议列表增删、banner 出现没有任何过渡，也没有 `accessibilityReduceMotion` 分支。
7. **颜色 token 太少**：Assets 里只有 Accent / SpeakerMe / SpeakerOther，原型的 success/warning/danger 在实现里是散落的系统色（`.green`/`.orange`/`.red`）与硬编码透明度（`.quaternary.opacity(0.4)`、`Color.secondary.opacity(0.06)`）。暗色模式下层次容易糊，也难统一调整。
8. **可访问性**：模型页/侧栏已补 `.accessibilityLabel`，但会议列表行、纪要工具条、字幕控制条缺标签与 `.help`；浮窗内没有完整键盘操作（字幕条只能用鼠标）。
9. **常规 macOS 快捷键缺失**：⌘, 打开设置、⌘1–4 切页、⌘W 关主窗口、Esc 关主窗口。
10. **字幕浮窗位置/大小不持久化**：`SubtitlePanelController` 每次启动都 `position(panel)` 到屏幕底部，用户拖动过的位置在重启后丢失（原型虽未明说，但这是该类工具的默认预期）。
11. **转写编辑没有保存回执**：`onSubmit` 后静默落盘，没有「已保存」提示；且垂直 `TextField` 里回车即保存，无法输入换行。
12. **模型页运行时区缺版本/芯片/GPU 信息**：原型底部 panel 有「版本 0.27.1 · Apple M3 Pro · GPU 可用」，实现只有 bannner + 日志入口。

---

## 4. 原型之外，建议顺手补的（评审中发现）

1. **残留模型服务进程**：本次检查时机器上有 6 个 `mlx_vlm.server` 进程（不同端口，来自多次启动/退出）。不属于 UI，但用户会从活动监视器/内存占用感知到，建议核查 `PIDRegistry.terminateAll()` 与异常退出的路径。
2. **停止纪要生成时保留并保存已生成内容**：现在 `CancellationError` 分支只把 `isGenerating` 置 false，`minutesText` 留在内存里，切走就丢。
3. **下载可暂停/续传的 UI**：`HFDownloader` 已有断点续传能力，UI 只差暂停/继续按钮（原型 P1-8 已给出形态）。
4. **长会议转写虚拟化**：`LazyVStack` 有了，但一分钟一句话 × 2 小时 = 上百条，建议加「跟随最新/跳到顶部」与时间轴锚点。

---

## 5. 打包

```bash
xcodebuild -project LingoLens.xcodeproj -scheme LingoLens -configuration Release \
  -derivedDataPath .xcodebuild build
# 再把 .xcodebuild/Build/Products/Release/LingoLens.app 与 /Applications 软链放进 dist 并 hdiutil 打包
```

产物：`dist/LingoLens-0.1.0.dmg`（21 MB，内含 47 MB 通用二进制 App + README + Applications 软链）。
签名为 ad-hoc（`CODE_SIGN_IDENTITY=-`），本机构建产物没有隔离属性可直接打开；发给他人的话需要开发者 ID 签名 + 公证。
当前 Assets 里还没有 `AppIcon`，安装后是系统通用图标。

## 6. 品牌标志

**对话镜头（Conversation Lens）**：圆环 = 镜头，左下尾巴让它同时是对话气泡，环内两行短线 = 原文 / 译文。
一个图形同时对应「看文字、听对话、记内容」三件事，且只有 4 个几何元素，16px 下仍可辨认。

- 渐变 `#5C63E8 → #3338A6`，白色标志；无内置阴影与文字。
- 已落盘：`App/Assets.xcassets/AppIcon.appiconset`（16–512@2x）、`BrandIcon.imageset`（侧边栏 20pt / 引导页 74pt），`project.yml` 设 `ASSETCATALOG_COMPILER_APPICON_NAME`。
- 源文件与生成脚本：`Resources/Brand/`（`make-icon.swift` 可重新渲染任意尺寸）。

## 7. 建议的落地顺序

1. 会议详情改成左右分栏（P0-4）—— 改动集中、体感最大。
2. 会话结束 toast + 跳转（P0-2）—— 半天量级，补上主流程闭环。
3. 菜单栏音频电平 + 字幕浮窗入口（P1-6/7）—— 会话可信度问题。
4. 首次启动引导（P0-1）—— 工作量最大，但决定新用户留存。
5. 错误体系收敛（P0-3）+ 会议列表/纪要定位细节（P1-1~5）。
6. 设置页二级导航与模型页下载卡（P1-8~12）。
7. P2 细节与动效、可访问性收尾。
