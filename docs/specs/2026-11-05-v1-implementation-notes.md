# LingoLens v1（桌面基础）实现说明

- 日期：2026-11-05
- 对应设计文档：[2026-11-05-lingolens-mac-design.md](2026-11-05-lingolens-mac-design.md)
- 范围：设计文档第 4–7 章、第 10–13 章中的“桌面基础”子项目

## 1. 交付内容

| 设计文档章节 | 实现位置 | 说明 |
|---|---|---|
| 3 模块划分 / 13 目录结构 | `Modules/*`、`App/`、`project.yml` | 每个模块独立 target；App 通过 XcodeGen 构建 |
| 4.1 Python 环境 | `ModelRuntime/PythonEnvironment.swift` | 内置 uv、Python 3.12、固定 mlx-vlm、版本标记、进度流、重装 |
| 4.2 ServerPool | `ModelRuntime/ServerPool.swift` | 一模型一进程、状态机、就绪轮询、崩溃重启、租约、空闲卸载、退出清理 |
| 5 ModelLibrary | `Modules/ModelLibrary` | 扫描、导入引用、HF 下载、模型信息、删除策略 |
| 6 设置 | `Modules/Settings`、`App/SettingsView.swift` | `settings.json`、场景参数、服务参数、目标语言、快捷键、开机启动 |
| 7 划词翻译 | `Modules/SelectionTranslate` | Carbon 快捷键、AX 取词、剪贴板兜底、非激活浮窗、语言检测、流式译文 |
| 7 LLMClient | `Modules/LLMClient` | `/v1/chat/completions` SSE、首字延迟/tok/s、取消 |
| 10 权限 | `SelectionTranslate/SelectionReader.swift`、`App/PermissionsSettingsView.swift` | 辅助功能状态与申请；麦克风状态（v2 使用） |
| 11 错误处理 | 各模块 `LocalizedError` + 界面提示 | 运行时失败、启动失败、内存不足、翻译失败等 |

## 2. 构建方式

- **SwiftPM（`Package.swift`）**：提供 5 个功能模块与 5 个测试 target，可用 `swift build` / `swift test` 在只有 Command Line Tools 的机器上验证。
- **XcodeGen（`project.yml`）**：生成 `LingoLens.xcodeproj`，编译 `App/` 并链接模块，产出菜单栏应用。
- App 源码只由 XcodeGen 工程编译，不放进 SwiftPM target，避免两套构建系统重复编译同一批 SwiftUI 源码。

## 3. 关键实现决策

### 3.1 ServerPool

- `ServerState`：`stopped → starting → ready → stopping`，失败进入 `failed(message)`。
- `ensure(model:config:)` 并发调用共享同一个 `Task`，避免同一模型重复启动。
- 引用计数通过 `ServerLease`：`acquire` / `release`；租约未释放时不会被空闲卸载。
- 空闲卸载由 `reapIdle` 完成（App 内每 30s 定时调用），只处理非常驻、无租约的模型。
- 崩溃后自动重启 1 次；5 分钟（`restartWindow`）内再次崩溃进入 `failed`，避免崩溃循环。
- 就绪探测轮询 `GET /v1/models`，默认超时 120s、间隔 0.5s。
- 就绪后读取 `/v1/models` 返回的模型标识（mlx-vlm 返回的是模型绝对路径），通过
  `ServerLease.serverModelID` 传给 Chat Completions 请求。**不能用应用内的模型名**：
  mlx-vlm 收到未知 model 名会卸载已加载模型并尝试加载同名模型。
- 启动前按 safetensors 总大小估算内存（权重 × 1.15 + 512MB），超过可用内存则拒绝启动。
- 仅监听 `127.0.0.1` 的系统分配端口；PID 记录写入 `runtime/servers.json`，下次启动清理残留。
- 日志在 `~/Library/Logs/LingoLens/<模型名>.log`。

### 3.2 Python 环境

- 通过内置 `Resources/uv/uv` 创建 `runtime/venv`，安装 `mlx-vlm==<固定版本>`。
- `runtime/installed.json` 记录 python / mlx-vlm 版本；版本变化时重装依赖。
- 安装进度通过 `AsyncStream<InstallProgress>` 暴露给 UI；失败保留日志可重试。
- uv 查找顺序：Bundle 内置 → `LINGOLENS_UV` → Homebrew / 用户目录 → PATH。

**安装加速与可观测（0.1.3）**

- 下载源：默认 `automatic` = 阿里云镜像优先，失败自动回退官方 PyPI；设置里可选清华 / 腾讯 /
  自定义索引。每次尝试都会重新执行 `uv pip install`，但复用同一个 uv 缓存。
- uv 环境变量：`UV_HTTP_TIMEOUT=60`、`UV_HTTP_RETRIES=5`、`UV_CONCURRENT_DOWNLOADS=8`、
  `UV_NATIVE_TLS=1`，以及 `UV_CACHE_DIR`（App 数据目录）、`UV_PYTHON_INSTALL_DIR`；
  设置里的代理写入 `HTTP(S)_PROXY` / `ALL_PROXY`。
- 进度：`InstallOutputParser` 解析 uv 的非交互输出（`Resolved N packages`、
  `Downloading <pkg> (12.3MiB)`、`Downloaded <pkg>`、`Installed N packages`），
  2 秒一次把「已下载/总数 + 当前包 + 已用时间」推给 UI，45 秒无输出提示网络较慢。
- 失败/取消：取消会向 uv 发 SIGTERM；没有 `installed.json` 就视为未安装，下次
  `ensureInstalled()` 自动重试，已下载的包从缓存复用。


### 3.3 ModelLibrary

- 扫描判定：目录含 `config.json` + 直系 `*.safetensors`，且 `config.quantization` 或目录名/父目录名含 `mlx`。
- 支持 HF 缓存布局（`models--org--name/snapshots/<hash>`），展示名从 `models--...` 还原。
- 模型信息：参数量（解析 safetensors 头部并累加张量元素数）、量化位数、磁盘大小、预估内存、视觉支持、上下文长度。
- 导入按引用登记，不复制；路径失效时标记“不可用”。
- HF 下载：`/api/models/<repo>` 列文件，逐文件 Range 续传到 `.part`，完成后原子改名；支持取消和进度。
- 删除：下载的模型删除文件；扫描 / 导入的只移出列表。

### 3.3.1 自动更新（Sparkle）

- `AppUpdater` 是 `SPUStandardUpdaterController` 的薄封装，同时实现 `SPUUpdaterDelegate`。
- `didFindValidUpdate` 时并行测速「官方地址 + 内置镜像」（每个源 64KB Range 请求，
  4 秒超时），结果缓存在内存里。
- `willDownloadUpdate` 用 `UpdateDownloadResolver.choose` 改写 `request.url`：
  官方可达时保持官方，镜像必须快 1.5 倍以上才切换，官方不可用时直接切镜像。
- 下载失败时在 `didFinishUpdateCycleFor:error:` 里换下一个未尝试过的源重试一次。
- 完整性依赖 appcast 的 EdDSA 签名，因此走第三方加速也不会被替换。
- 设置项 `update.source`：`automatic` / `official` / `custom`（支持 `{url}` 占位符）。

### 3.3.2 会议音频落盘

- 采集回调给出的缓冲区本身已是深拷贝（两路 Tap 都调 `AudioBufferTools.copy`），
  可以安全地同时交给识别器和录音器。
- `ChannelAudioRecorder` 统一录成 **16 kHz 单声道 AAC（32 kbps）**：和识别器输入一致，
  体积约 16 MB/小时，可直接用于事后重转写与识别效果比对。
- 已经是目标格式时跳过 `AVAudioConverter` 直接写文件——转换器每次调用都有缓冲延迟，
  逐块转换会累积丢帧；只有 48 kHz 立体声这类采集格式才走转换 + 混音。
- 写入跑在私有串行队列上，不阻塞采集回调与主线程；`finish()` 会阻塞到队列排空再返回。
- 会话结束时把实际落盘的通道登记进 `meta.json` 的 `audioFiles`（旧数据没有该字段，解码时容忍缺失）；
  某一路没有产生音频就删掉空文件、不登记。

### 3.3.3 Whisper 转写（可选引擎）

系统 SpeechAnalyzer 的模型是「一句一种语言」，中英混说时英文缩写会被中文模型按读音音译
（实测 ES →「淹死」、API latency → ATI LantonC）。补英文识别器无效：语言判定是句级的，
而混说是词级的；AnalysisContext.contextualStrings（官方词表偏置）实测对 SpeechTranscriber
完全没有影响，三个不同词表输出逐字节相同。

因此增加 Whisper 引擎（mlx-audio，已在 mlx-vlm 的依赖里，无需新增包）：

- **边车进程**：Resources/stt/lingolens_stt.py，常驻；标准输入灌 16 kHz 单声道 int16 PCM，
  标准输出按行给 JSON。模型加载约 1.8 秒，逐句起进程不可行，所以必须常驻。
- **自己断句**：能量检测。句尾静音 0.42 秒断句；超过 9 秒优先在「词间停顿」处切
  （rms 小于 3 倍静音阈值），硬上限 25 秒（Whisper 窗口 30 秒）。
  硬切会把字词劈开，实测会认错甚至输出繁体（那個查詢），软切判据就是为此加的。
- **默认简体提示**：中文场景传 initial_prompt「以下是普通话会议记录，请用简体中文转写。」，
  压住繁体输出。
- **领域词表**：设置里的 speech.hotwords 传给 hotwords，能显著提高英文缩写命中率
  （实测不加时 PRD → PRT、beta → Bit）。
- **模型分发**：SpeechModelInstaller 从魔搭下载 whisper-large-v3-turbo-q4（464 MB，4 bit）。
  不用 HuggingFace：本机直连完全超时，魔搭 2.6 MB/s。权重与 config 来自量化仓库，
  分词器文件来自官方仓库，两个来源在清单里分开声明。
- **取舍**：Whisper 按句出字幕，没有实时草稿；峰值内存约 0.73 GB。
  未选 Whisper 或模型没下好时自动回退系统识别，不会没有字幕。

### 3.6 辅助功能授权（macOS TCC）

- 判定用 `AXIsProcessTrusted()`，但 macOS 会把结果**缓存在进程里**：用户在系统设置里勾选之后，
  已经在运行的进程仍然读到 false，必须重启一次。之前文案写「授权后无需重启」是错的，
  这正是「明明开了却一直提示未授权」的根因。
- 为了区分「真的没授权」和「授权了但本进程没生效」，`AccessibilityPermission.resolvedState()`
  起一个**子进程**跑同一个二进制（`--accessibility-trust-check`）读判定：同一 app 身份、
  全新进程，不受缓存影响。三种结果对应三种 UI：已授权 / 未授权（去授权）/ 需要重启（重启按钮）。
- 这个命令行开关放在 `@main` 的最前面（`LingoLensMain.main()`），早于 SwiftUI 初始化，
  打印一行就 exit；放到 `applicationWillFinishLaunching` 不可靠。
- 实测：同一 bundle id 的两个不同构建（不同 cdhash）在全新进程里都读到 true，
  说明授权是按 bundle id 记的、能跨版本保留；所以升级不会丢掉授权。

### 3.7 更新包下载（0.1.7 修正）

日志证据（2026-11-09 13:36–13:37）：

    github 直连         full 24MB → 504 gateway timeout（2MB Range 却有 191 KB/s）
    gh-proxy.com        full 24MB → 504（2MB Range 176 KB/s）
    ghfast.top          full 24MB → 200，1.6–5.7 MB/s，sha256 与本地一致

结论：**分块测速无法预测「能不能下完」**。0.1.4 引入的测速择优会稳定选中
「小请求很快、整包必超时」的官方直连，反而必然失败；0.1.6 的换源又只推进一次，
没走到真正可用的 ghfast.top。

0.1.7 的做法：

- 删掉测速择优（`UpdateDownloadResolver.choose` 与 `UpdateSourceProbe` 一并删除）。
  测速带来的错误决策比它解决的问题多。
- 候选顺序改为 **镜像优先、官方兜底**：`automatic` = [ghfast.top, gh-proxy.com, 官方]。
- 换源改为**穷尽式**：`failedToDownloadUpdate` 里直接推进到下一个未尝试的候选并重试
  （不再依赖 `didFinishUpdateCycleFor`，那条路径实测只触发一次）；候选耗尽才提示失败。
- 过程写 `~/Library/Logs/LingoLens/app.log`，菜单栏应用看不到 stdout，之前只能靠猜。

### 3.8 首启自动下载模型（0.1.9）

之前用户要自己「模型页 → 从 Hugging Face 下载 → 输入仓库名 → 等 → 设为常驻模型」，
而且 `HFDownloader` 把 `huggingface.co` 写死——国内实测直连直接超时，这条路根本走不通。

- **下载源**：新增 `ModelDownloadSource`：`automatic` 默认先走魔搭
  （`https://www.modelscope.cn/api/v1/models/{repo}/repo/files` 列文件、
  `/models/{repo}/resolve/master/{file}` 下载），失败再回退 Hugging Face。
  实测魔搭 LFS 文件 3.6–5.7 MB/s，Hugging Face 直连超时。
- 注意 `ModelSource`（模型从哪来：扫描/导入/下载）与 `ModelDownloadSource`
  （文件从哪个站下）是两件事，不要混用。
- **自动开始**：引导走到「选择模型」且本机没有可用模型时，自动把
  `HFDownloader.recommendedRepositoryID`（`mlx-community/Qwen3.5-4B-MLX-4bit`）
  交给 `ModelDownloadState` 下载，进度直接复用模型页的下载卡片；用户可随时取消或改为导入。
- **自动常驻**：`downloadModel` 完成后调用 `applyDefaultResidentModelIfNeeded()`，
  下载结束即设为常驻模型，不用再点一次。

### 3.4 设置

- `~/Library/Application Support/LingoLens/settings.json`，300ms 防抖落盘。
- 所有字段解码都容忍缺失，便于版本演进。
- 场景默认参数遵循文档 6.2；thinking 关闭时请求体带 `chat_template_kwargs.enable_thinking=false`。
- 服务参数按模型保存，修改后点击“应用并重启”对运行中的进程生效。

### 3.5 划词翻译

- Carbon `RegisterEventHotKey`，默认 `⌥D`，设置页可录制修改；修改后立即重新注册。
- 取词顺序：AX `kAXSelectedTextAttribute` → 备份剪贴板 + 模拟 ⌘C + 恢复 → 空浮窗手动输入。
- 浮窗为 `.nonactivatingPanel`，层级 `.floating`，不激活 App；单实例、再次触发替换内容。
- 译文流式追加；底部显示“模型 · 首字延迟 · tok/s”；支持复制、固定、Esc 关闭。
- 原文输入框用 `NSTextView` 接管按键：单独按 ↩ 立即翻译（无需组合键），⇧↩ / ⌥↩ 换行；非编辑态按 ↩ 重译，空文本时先切到输入框。
- `NLLanguageRecognizer` 检测原文语言，与目标语言相同则自动改译英文。

## 4. 验证结果（Xcode 27.2）

- `xcodegen generate`：成功生成工程。
- `xcodebuild ... build`：**BUILD SUCCEEDED**，ad-hoc 签名成功，App 包内含 `Resources/uv/uv`，`LSUIElement=true`。
- `xcodebuild ... test`：**TEST SUCCEEDED**，55 个常规用例通过（2 个真实模型用例默认跳过）。
- `swift test`（SwiftPM）：常规用例全部通过。
- 真实模型集成（`Qwen3.5-4B-MLX-4bit` + `mlx-vlm 0.7.12`）：
  - 直接调用 server：翻译 `hello` → `你好`，4.85s 通过。
  - 走 `TranslationService` 全链路：3.21s 通过。
- 启动冒烟测试：App 运行 6 秒无崩溃，按预期创建 `Application Support/LingoLens` 与日志目录。
- 真机完整链路：启动 App → 扫描到 `~/mlx-models/Qwen3.5-4B-MLX-4bit` → 自动设为常驻模型 →
  启动 `mlx_vlm.server` → `/v1/models` 返回 loaded=true → 通过 AppleScript 退出 → 子进程与
  PID 记录均被清理。
- 固定版本：Python 3.12 + `mlx-vlm==0.7.12`；已确认 `--kv-bits`、`--max-kv-size` 参数存在。

## 5. 测试覆盖

`swift test` 共 57 个用例，其中 55 个常规用例默认运行、2 个需真实模型的集成用例默认跳过：

- **ModelRuntime**：ServerPool 启动/复用、服务端模型标识、空闲卸载、租约保护、常驻不卸载、崩溃重启一次、内存拦截、就绪超时、shutdown；Python 环境安装/复用/版本重装/缺少 uv；服务参数拼装；端口分配；PID 文件；内存估算；日志名安全化。
- **ModelLibrary**：模型目录识别、量化/视觉/上下文解析、safetensors 参数统计、目录名 mlx 回退、扫描过滤、列表持久化与删除策略、可用性刷新、HF 仓库校验与路径编码。
- **LLMClient**：SSE 分块/CRLF/多行/注释、请求体与 thinking、流式增量与 usage、HTTP 错误、场景默认参数。
- **Settings**：默认值、缺省字段解码、往返一致、模型解析、磁盘读写、Store 落盘、快捷键显示/归一化。
- **SelectionTranslate**：语言检测与目标语言回退、提示词约束、支持语言列表、错误文案。

集成测试位于 `Tests/LLMClientTests/IntegrationTests.swift` 与
`Tests/SelectionTranslateTests/TranslationServiceIntegrationTests.swift`，默认跳过；设置
`LINGOLENS_INTEGRATION_MODEL` 指向本地模型目录后运行：

```bash
LINGOLENS_INTEGRATION_MODEL=~/mlx-models/Qwen3.5-4B-MLX-4bit swift test --filter Integration
```

两个用例都会启动真实 `mlx_vlm.server`：一个直接调用 Chat Completions，另一个走
`TranslationService`（设置解析 → 模型选择 → 租约 → 流式翻译）完整链路。本机已用
`Qwen3.5-4B-MLX-4bit` 实际跑通（约 3–5 秒）。

## 6. 与设计文档的偏差 / 待办

- 设计文档以 XcodeGen 为唯一工程；本实现额外提供 SwiftPM 包，便于无 Xcode 环境下编译与测试模块。
- 字幕浮窗、点击穿透、麦克风/系统音频采集、会议页与纪要生成已在 v2/v3 实现，
  见 [v2/v3 实现说明](2026-11-05-v2-v3-implementation-notes.md)。
- 模型服务参数名（`--kv-bits`、`--max-kv-size`）依赖固定版本 mlx-vlm，升级时需核对；界面提供“应用并重启”和服务参数覆盖。
- 未做代码签名配置与公证；首版按文档要求本地签名运行。

## 7. 手动验收建议

1. `swift test` 全绿。
2. `xcodegen generate` 后构建 App，确认菜单栏图标出现、无 Dock 图标。
3. 导入或下载一个 MLX 模型，设为常驻，确认启动后 `/v1/models` 可访问且日志有输出。
4. 在 Safari / VS Code / 微信中选中文字，按 ⌥D，确认浮窗出现、流式译文、首字延迟与 tok/s 显示。
5. 修改快捷键、目标语言、场景参数，确认设置落盘并生效。
6. 关闭 App，确认无残留 `mlx_vlm.server` 进程。
