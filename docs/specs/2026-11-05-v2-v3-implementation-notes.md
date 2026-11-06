# LingoLens v2 / v3（实时音频翻译、会议纪要）实现说明

- 日期：2026-11-05
- 对应设计文档：[2026-11-05-lingolens-mac-design.md](2026-11-05-lingolens-mac-design.md) 第 8、9 章
- 前置实现：[v1 桌面基础](2026-11-05-v1-implementation-notes.md)

## 1. 交付范围

| 设计文档章节 | 实现位置 | 说明 |
|---|---|---|
| 8.1 音频会话 | `App/AudioSessionController.swift` | 开始/停止、双路语言、显示字幕 / 记录会议开关 |
| 8.2 AudioCapture | `Modules/AudioCapture` | Core Audio Process Tap 系统音频 + AVAudioEngine 麦克风（voice processing） |
| 8.3 Transcriber | `Modules/Transcriber` | 每路一个 SpeechAnalyzer + SpeechTranscriber，partial/final、模型下载 |
| 8.4 LiveSubtitle | `Modules/LiveSubtitle` | 底部字幕浮窗、逐句翻译、上下文、积压合并、点击穿透 |
| 9.1 会议记录 | `Modules/Meetings/MeetingStore.swift` | 每场一个目录、meta.json、transcript.jsonl 实时追加、minutes.md |
| 9.2 会议页 | `App/MeetingsView.swift` | 列表、详情、搜索、逐条编辑、纪要生成/编辑/复制/保存 |
| 9.3 纪要生成 | `Modules/Meetings/MinutesGenerator.swift` | 模板、输出语言、长会议分段提炼、流式生成、停止 |
| 6 设置扩展 | `Modules/Settings/AppSettings.swift` | 音频来源/语言/记录会议、字幕翻译与目标语言 |

## 2. 关键实现

### 2.1 AudioCapture

- 系统音频：`CATapDescription(monoGlobalTapButExcludeProcesses:)`（排除本应用进程）→
  `AudioHardwareCreateProcessTap` → 以默认输出设备为主时钟创建私有聚合设备 → IOProc 回调拿到 PCM。
- 麦克风：`AVAudioEngine.inputNode`，开启 `setVoiceProcessingEnabled(true)` 做回声消除。
- 两路统一打上 `.other` / `.me` 标记，通过 `AsyncStream` 交给转写层；实时回调里深拷贝缓冲区。
- 单路失败不会拖垮另一路，失败原因通过 `warnings` 暴露到状态栏文案。

### 2.2 Transcriber

- 启动时为每路安装/校验系统语音模型（`AssetInventory`），再创建 `SpeechAnalyzer`。
- 输入格式取 `SpeechAnalyzer.bestAvailableAudioFormat`，采集格式与目标格式不同时用
  `AVAudioConverter` 流式转换；`AnalyzerInput` 送入分析器。
- `SpeechTranscriber.Result.isFinal` 区分 partial / final；partial 只更新字幕原文，final 触发翻译与会议落盘。
- 停止时先结束输入流、再 `finalizeAndFinishThroughEndOfInput`，最多等 5 秒收集最后结果。

### 2.3 LiveSubtitle

- 半透明置顶 `NSPanel`，默认屏幕底部居中，可拖动、可缩放；支持点击穿透（菜单栏/设置页切换）。
- 每路颜色不同（我 = 蓝，对方 = 绿），原文小字、译文大字；partial 以更低透明度显示。
- 翻译策略：每句 final 翻译，携带同路最近 2 句作为上下文；积压超过 3 句时合并为一次请求，
  按行分配译文，行数对不上时整段落到最后一句。
- 合并请求会按句数提高 `max_tokens`，避免字幕被截断；翻译失败该句标 ⚠，不阻塞后续。
- 每路可独立设置“是否翻译 + 目标语言”，默认对方 → 中文、我 → 不翻译。

### 2.4 Meetings

- 目录：`~/Library/Application Support/LingoLens/meetings/<yyyy-MM-dd-HHmmss>/`。
- `meta.json`（标题、起止时间、语言）、`transcript.jsonl`（`{id,time,speaker,text,translation?}`，逐行追加）、`minutes.md`。
- 翻译完成后通过条目 id 回写 `translation`；会议页支持搜索、逐条编辑（回车保存）、改标题、删除。
- 纪要模板持久化在 `minutes-templates.json`，标准模板不可删除，可编辑/新建/删除自定义模板。
- 长会议：按 CJK/ASCII 估算 token，与模型上下文（`modelContextOverrides` 或 config 的
  `max_position_embeddings`）比较；超出时按时间切段分别提炼要点，再合并生成最终纪要。
- 输出语言可选，流式显示，可停止、重新生成、手动编辑、复制 Markdown、保存 `.md`。

### 2.5 界面入口

- 菜单栏：开始/停止音频会话、显示/隐藏字幕、点击穿透、音频来源、每路语言、会话状态。
- 主窗口“设置”：音频会话、字幕翻译、模板管理入口与原有模型/场景/服务/权限配置。
- 主窗口“会议”：左侧会议列表，右侧转写与纪要区。

## 3. 验证结果

- `swift build` / `xcodebuild build`：**BUILD SUCCEEDED**（ad-hoc 签名）。
- `swift test`：77 个常规用例全部通过；4 个真实模型/语音文件集成用例默认跳过。
- `xcodebuild test`：**TEST SUCCEEDED**。
- 真实语音文件转写：用 `say` 生成中文语音，`SpeechTranscriptionSession` 成功转出文字（3.3s）。
- 真实模型纪要生成：`Qwen3.5-4B-MLX-4bit` 从两句话的转写生成 Markdown 纪要（5.1s）。
- App 启动冒烟：主窗口、常驻模型服务、退出清理均正常。
- 新增单测覆盖：音频深拷贝/重采样、字幕 partial/final、裁行、翻译批处理与行分配、
  会议 JSONL 读写/编辑/结束、长会议切段、纪要模板与提示词。

尚未自动化验证（需真实设备/权限）：

- 系统音频 Tap 的实际采集（需要 TCC“系统音频录制”授权）。
- 麦克风采集与 voice processing 的回声效果。
- Zoom / Teams 场景的双语字幕与 1 小时会议纪要。

## 4. 已知限制

- 音频设备选择未实现：系统音频取默认输出，麦克风取系统默认输入。
- 会议音频默认不保存，设计文档中的可选 `m4a` 尚未实现。
- 系统音频权限只能由系统弹窗/设置页管理，应用内没有主动查询状态的 API。
- 字幕字号/透明度已进设置模型，但暂无对应 UI 控件（使用默认值，可在 `settings.json` 调整）。
- 会议页暂不支持按标题搜索（仅转写内搜索）。
- 说话人分离仍限定“我 / 对方”两路。

## 5. 手动验收建议

1. 设置 → 权限：授权辅助功能、麦克风；首次开始音频会话时允许“系统音频录制”。
2. 播放一段英文视频，开始音频会话，确认字幕浮窗出现原文与中文译文。
3. 用麦克风说中文，确认“我”这一路可显示（默认不翻译），无回声重复。
4. 打开“记录会议”，进行一段对话，停止后在会议页检查转写、搜索、编辑。
5. 选择模板与输出语言，生成纪要；确认流式输出、停止、重新生成、复制与保存。
6. 外放场景检查 voice processing 是否抑制了对方声音的重复转写。

## 6. 修复记录（2026-11-06）

### 实时字幕只在停止后一次性出现

现象：开始音频会话后能听到声音、电平条也在跳，但字幕浮窗长时间没有文字，停止后才一次性出现。

原因：`SpeechTranscriptionSession` 创建 `SpeechTranscriber` 时用的是自定义选项
`transcriptionOptions: []、reportingOptions: [.volatileResults]`。这套选项能正常出结果，但要等到
end-of-input（`finalizeAndFinishThroughEndOfInput`）才把结果吐出来，等于把流式识别退化成了批处理。
对照实验：同样的音频、同样的实时喂入节奏，`preset: .progressiveTranscription` 会在说话过程中持续产出
volatile 结果，自定义空选项直到结束才产出。

修复：改用 `SpeechTranscriber(locale:preset:.progressiveTranscription)`。

顺带：
- 新增 `TranscriptionLog`（`~/Library/Logs/LingoLens/transcriber.log`），记录每路会话的语言/格式、
  缓冲计数、转换失败、结果到达与结束原因；菜单栏应用没有控制台，这类问题没有日志只能靠猜。
- 输入格式变化时重建 `AudioFormatConverter`，避免切换设备后静默丢包。

### 实时字幕一直停在「等待语音…」（电平条却在跳）

现象：菜单栏开始音频会话后，电平条正常起伏、说明麦克风采到了声音，但字幕浮窗始终是
「等待语音…（在菜单栏开始音频会话）」。

原因：内建麦克风是三麦克风阵列（3 声道）。开启 voice processing 后，输入节点的输出格式会变成
**9 声道、`kAudioChannelLayoutTag_DiscreteInOrder` 布局**。这种离散布局没有声道标签，
`AVAudioConverter` 把它降到单声道时不会报错：返回 `.haveData`、帧数也正常，但采样值全是 0。
于是 `SpeechAnalyzer` 收到的是一段数字静音，永远不会出结果；而电平条算的是**转换前**的原始
缓冲，所以看起来一切正常。

日志特征（`transcriber.log`）：
```
[me] first buffer format=<... 9 ch, 48000 Hz, Float32, deinterleaved> frames=4800
[me] buffers=600 outFrames=959824 convertFailures=0 results=0
```
`outFrames` 在涨、`convertFailures=0`、`results=0`，就是「转换成功但输出静音」。

修复：`AudioFormatConverter` 在输入/输出声道数不一致时自己混音——逐声道求和取平均，
再交给 `AVAudioConverter` 只做采样率与位深转换；同时加了静默兜底（输入有信号、输出全 0 时
抛 `AudioConversionError.silentOutput`，写进日志而不是继续喂静音）。
回归测试：`Tests/AudioCaptureTests` 里用 9 声道 `DiscreteInOrder` 缓冲断言转换成单声道后
RMS 不为 0；用真实中文语音铺成 9 声道验证，修复前识别结果为 0 条，修复后逐字上屏。

### Teams 会议里「对方的声音采集不到」+「一开音频会话音量就变小」

现象：开着 Teams 开会时开始音频会话，对方说话的字幕完全没有；同时听感上 Teams 的音量
被压低了，调 Teams 自己的音量也补不回来。

原因：`MicrophoneCapture` 为了让外放不漏音，调用了
`inputNode.setVoiceProcessingEnabled(true)`（AUVoiceIO）。实测 AUVoiceIO 和 Core Audio
的进程 Tap 不能共存，而且会 duck「其它音频」：

| 场景 | 系统音频 Tap |
|---|---|
| 只有 Tap | 正常，1.2s 收 120 个缓冲，RMS≈0.16 |
| Tap → 普通 `AVAudioEngine`（不开 VP） | 正常，RMS≈0.14–0.23 |
| Tap → VP 引擎 | **约 0.4s 后停止出数据**（正好是日志里 `[other] buffers=40`） |
| VP 引擎 → 新建 Tap | **一帧都没有** |
| VP 在另一个进程 | Tap 能收，但音量被 duck 到 RMS≈0.004（约 −32 dB） |

所以：对方的声音不是没采，是被 VP 掐断了；音量变小是 VP 的
`voiceProcessingOtherAudioDuckingConfiguration` 默认 ducking 把「其它音频」压下去。

修复：`MicrophoneCapture` **不再开启 voice processing**，让回音消除让位给系统音频采集。
代价：外放时对方的声音会从麦克风串进来（`me` 通道可能重复转写对方的话），**建议开会戴耳机**。
如果以后要做回音消除，必须同时换掉系统音频的采集方式（VP 与进程 Tap 不能共存）。
