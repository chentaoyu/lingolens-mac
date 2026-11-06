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
