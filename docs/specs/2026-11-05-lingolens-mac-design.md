# LingoLens for macOS 设计文档

- 日期：2026-11-05
- 状态：待评审
- 定位：独立的 macOS 原生桌面应用，与浏览器插件无关联、不共享代码或服务

## 1. 目标与范围

一个完全本地运行的翻译与会议助手：

1. **划词翻译**：任意应用中选中文字，按快捷键弹出浮窗显示译文
2. **实时语音翻译**：采集系统音频（对方）与麦克风（我方），实时转写并在浮窗显示双语字幕
3. **会议纪要**：会议中实时保存转写，结束后手动生成纪要

约束：

- 全部本地推理：LLM 使用内置的 mlx_vlm server，语音识别使用系统 SpeechAnalyzer
- 不接入任何外部模型供应商
- 仅支持 Apple Silicon，最低 macOS 26（SpeechAnalyzer 需要）
- 首版仅本地签名运行，不做公证与自动更新

非目标（首版不做）：外部供应商、推荐模型列表、说话人分离（多于"我/对方"两路）、OCR、写作助手、云同步。

## 2. 技术选型

- SwiftUI + Swift 6，项目用 XcodeGen 管理（`project.yml`），各模块为独立 target
- 菜单栏常驻（`MenuBarExtra`）+ 主窗口（模型 / 设置 / 会议），默认不显示 Dock 图标
- LLM：应用托管的 Python 运行时 + `mlx_vlm.server`（OpenAI 兼容接口）
- 语音识别：`SpeechAnalyzer` + `SpeechTranscriber`
- 系统音频：Core Audio Process Tap；麦克风：`AVAudioEngine`

## 3. 模块划分

| 模块 | 职责 | 依赖 |
|---|---|---|
| `ModelRuntime` | Python 环境（uv + mlx-vlm）、server 进程池 | — |
| `ModelLibrary` | 扫描 / 导入 / 下载模型，读取模型信息 | — |
| `LLMClient` | 向本地 server 发流式请求，应用场景参数，统计性能 | ModelRuntime |
| `Settings` | 常驻模型、场景配置、通用设置的读写 | — |
| `SelectionTranslate` | 全局快捷键、取选中文本、翻译浮窗 | LLMClient, Settings |
| `AudioCapture` | 系统音频 + 麦克风双路采集 | — |
| `Transcriber` | 每路独立流式转写，输出"我 / 对方"终句 | AudioCapture |
| `LiveSubtitle` | 字幕浮窗，逐句翻译双语展示 | Transcriber, LLMClient |
| `Meetings` | 转写实时落盘、会议列表、纪要生成与导出 | Transcriber, LLMClient |

子项目拆分（各自独立出实现计划，按顺序交付）：

1. **桌面基础**：App 外壳 + ModelRuntime + ModelLibrary + LLMClient + Settings + SelectionTranslate
2. **实时音频翻译**：AudioCapture + Transcriber + LiveSubtitle
3. **会议纪要**：Meetings

## 4. ModelRuntime

### 4.1 Python 环境

- App 包内置 `uv` 二进制
- 首次启动在 `~/Library/Application Support/LingoLens/runtime/` 创建 Python 3.12 环境并安装**固定版本**的 mlx-vlm，UI 显示进度
- 环境目录写入版本标记；App 升级若固定版本变化，仅重装依赖
- 安装失败显示日志与"重试"，模型管理等功能不受影响

### 4.2 进程池 `ServerPool`（actor）

- 唯一入口：`ensure(model) async throws -> URL`，已运行直接返回 baseURL，否则启动：
  `python -m mlx_vlm.server --model <path> --host 127.0.0.1 --port <随机空闲端口> <服务参数>`
- **一个模型一个进程**：使用同一模型的场景共享进程
- 状态机：`stopped → starting → ready → stopping`
  - 启动后轮询 `/v1/models` 直到就绪，超时 120s
  - 崩溃后自动重启 1 次，再失败进入错误状态
- **常驻模型**：App 启动即加载，不做空闲卸载；更换常驻模型时重启该进程
- **独立模型**：首次请求时启动；进行中的请求持有引用计数，不会被中途关闭；空闲 N 分钟（默认 10，可配）后 SIGTERM
- **内存预检**：加载前用 safetensors 总大小估算内存，与可用内存比较，不足则拒绝加载并提示
- **清理**：App 退出时对子进程 SIGTERM，5s 后 SIGKILL；记录 PID 文件，启动时清理上次残留
- 只监听 `127.0.0.1` 随机端口，仅供应用自身使用
- 日志写入 `~/Library/Logs/LingoLens/<模型名>.log`，UI 可一键打开

## 5. ModelLibrary

- **扫描**：默认扫描 `~/mlx-models`、`~/.cache/huggingface/hub`、`~/.lmstudio/models` 与应用模型目录，扫描目录可增删
  - 判定：目录含 `config.json` + `*.safetensors`，且 config 含 MLX 量化信息或目录名含 `mlx`
  - 启动时及点击"刷新"时扫描
- **导入**：选择文件夹，按**引用**登记（只记录路径，不复制）；路径失效标记"不可用"
- **下载**：输入 Hugging Face repo ID，直接调用 HF 文件 API 下载到 `~/Library/Application Support/LingoLens/models/`，支持断点续传、进度、取消
- **模型信息**：参数量、量化位数、磁盘大小、预估内存、是否支持视觉（读 config）
- **删除**：下载的模型删除文件；扫描 / 导入的仅移出列表

## 6. 设置

存储于 `~/Library/Application Support/LingoLens/settings.json`。

### 6.1 常驻模型

默认 Qwen3.5-4B-MLX-4bit；首次启动找不到时引导去下载页。

### 6.2 场景

每个场景可选"使用常驻模型"（默认）或指定独立模型，并有独立的生成参数：

| 场景 | 特点 | 默认参数 |
|---|---|---|
| 划词翻译 | 偶发、短文本、首字延迟优先 | temperature 0.2，max_tokens 1024，thinking 关 |
| 实时字幕 | 持续、高频、1–3 句 | temperature 0，max_tokens 256，thinking 关 |
| 会议纪要 | 会后一次性、长输入、质量优先 | temperature 0.3，max_tokens 4096，thinking 关（可开） |

生成参数：temperature、top_p、max_tokens、repetition_penalty、thinking 开关。thinking 关闭时请求带 `chat_template_kwargs.enable_thinking=false`。

### 6.3 服务参数（按模型）

KV cache 量化位数、最大 KV 长度、空闲卸载分钟数（常驻模型不适用）。修改后重启该模型进程生效。具体命令行参数以固定版本 mlx-vlm 实际支持的为准。

### 6.4 通用

目标语言（默认简体中文）、划词快捷键（默认 ⌥D）、开机启动（`SMAppService`）。

## 7. 划词翻译

- 全局快捷键：系统 `RegisterEventHotKey`，可自定义
- 取选中文本：
  1. Accessibility API 读取焦点元素的 `kAXSelectedTextAttribute`
  2. 失败则备份剪贴板 → 模拟 ⌘C → 读取 → 恢复剪贴板
  3. 仍无文本则打开空浮窗供手动输入
- 浮窗：非激活 `NSPanel`，出现在鼠标附近，不抢焦点；同时只存在一个，再次触发替换内容
  - 原文（可编辑，⌘Enter 重译）、译文（流式）、底部灰字：模型名 · 首字延迟 · tok/s
  - `NLLanguageRecognizer` 检测原文语言，与目标语言相同时自动改译英文
  - 复制、固定（固定后点外部不关闭）、Esc 关闭
  - 模型未就绪时显示"模型加载中…"

### LLMClient

- `POST /v1/chat/completions`（stream），`URLSession.bytes` 解析 SSE，对外为 `AsyncThrowingStream<String>`
- 取消 Task 即中断请求（关闭浮窗、重译时）
- 记录首字延迟、耗时、token 数（取 server 返回的 `usage`）

## 8. 实时音频翻译

### 8.1 音频会话

字幕与会议记录共用"音频会话"（采集 + 转写），开始时两个独立开关：**显示字幕**、**记录会议**，可任意组合。控制入口在菜单栏：开始 / 停止、选择音频源（系统 / 麦克风 / 两者）、每路语言。

### 8.2 AudioCapture

- 系统音频：`CATapDescription`，默认"全部系统音频，排除本应用"，也可勾选指定应用
- 麦克风：`AVAudioEngine` 输入节点，可选设备，开启 voice processing（回声消除），避免外放时重复转写对方声音
- 两路各自输出 16kHz 单声道 PCM，标记"对方""我"

### 8.3 Transcriber

- 每路一个 `SpeechAnalyzer` + `SpeechTranscriber`，独立运行
- 语言需指定（不自动检测）：会话开始时为每路选择，默认 对方 = 英文、我 = 中文，记住上次选择
- 首次使用某语言通过 `AssetInventory` 自动下载语音模型
- 输出 partial（字幕中灰色显示）与 final（触发翻译、写入会议记录）

### 8.4 LiveSubtitle

- 半透明置顶浮窗，默认屏幕底部，可拖动缩放，可切换点击穿透
- 显示最近 3–5 条：原文小字、译文大字，"我 / 对方"不同颜色
- 每路可单独设置是否翻译及目标语言，默认 对方 → 中文、我 → 仅显示原文
- 翻译策略：每个 final 句子翻译，附带前 2 句作为上下文；待翻译积压超过 3 句时合并为一次请求，保证跟上语速

## 9. 会议纪要

### 9.1 记录

每场会议一个目录 `~/Library/Application Support/LingoLens/meetings/<日期-时间>/`：

- `meta.json`：标题、起止时间、语言
- `transcript.jsonl`：每个 final 句子 `{time, speaker: "me"|"other", text, translation?}`，**实时追加**，崩溃不丢
- `minutes.md`：生成的纪要
- 默认不保存音频，可选同时保存 m4a

### 9.2 会议页

- 列表：标题（可改，默认日期时间）、时长、是否已有纪要
- 详情：带时间戳与"我 / 对方"标记的转写，可搜索、可逐条编辑；右侧为纪要区

### 9.3 生成

- 会后手动点击"生成纪要"，不做会中实时生成
- 选择模板（默认：摘要 / 关键讨论 / 决策 / 行动项（负责人、截止时间）/ 待定问题；模板为可编辑提示词，可新建）与输出语言
- 使用"会议纪要"场景的模型与参数，可临时覆盖；独立模型此时才加载，用完按空闲策略卸载
- 流式输出，可停止、重新生成、手动编辑
- 长会议：估算转写 token 数与模型上下文长度（读 config 的 `max_position_embeddings`，可在设置覆盖）比较；超出则按时间切段分别提炼要点，再合并为最终纪要
- 导出：复制 Markdown / 保存 `.md`

## 10. 权限

首次用到对应功能时才申请；设置页提供权限状态面板与跳转。

| 权限 | 用途 | 拒绝后的降级 |
|---|---|---|
| 辅助功能 | 读取选中文本 | 改用模拟 ⌘C；再失败则空浮窗手动输入 |
| 系统音频录制 | 采集系统音频 | 禁用该路，仅麦克风 |
| 麦克风 | "我"这一路 | 禁用该路，仅系统音频 |

## 11. 错误处理

| 场景 | 处理 |
|---|---|
| 运行时安装失败 | 保留日志，提示重试；模型管理仍可用 |
| 模型启动失败 / 崩溃 | 自动重启 1 次；仍失败在界面显示错误 +"查看日志" |
| 内存不足 | 启动前拦截，建议换小模型或关闭独立模型 |
| 划词翻译请求失败 | 显示错误与"重试" |
| 字幕翻译失败 | 跳过该句并标 ⚠，不阻塞后续 |
| 转写中断（设备拔出、语音模型未下载） | 会话显示"已暂停"，设备恢复后自动继续，已记录内容保留 |
| 纪要生成失败 | 保留已生成内容，可继续或重新生成 |

## 12. 测试

- **单元测试（Swift Testing）**：模型目录识别与信息解析、SSE 解析、场景参数合并、ServerPool 状态机（mock 进程层：空闲卸载、引用计数、崩溃重启）、transcript JSONL 读写、长会议切段
- **集成测试**（本地运行，无模型时跳过）：启动真实 mlx_vlm.server 跑一次翻译，校验输出与首字延迟
- **手动验收**：Safari / VS Code / 微信中划词翻译；Zoom/Teams 会议双语字幕；1 小时会议生成纪要；外放时的回声情况

## 13. 目录结构（规划）

```
lingolens-mac/
├── project.yml
├── App/                  # App 入口、菜单栏、主窗口
├── Modules/
│   ├── ModelRuntime/
│   ├── ModelLibrary/
│   ├── LLMClient/
│   ├── Settings/
│   ├── SelectionTranslate/
│   ├── AudioCapture/
│   ├── Transcriber/
│   ├── LiveSubtitle/
│   └── Meetings/
├── Resources/uv          # 内置 uv 二进制
├── Tests/
└── docs/specs/
```
