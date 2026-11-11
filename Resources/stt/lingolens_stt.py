#!/usr/bin/env python3
"""LingoLens 本地语音转写边车（Whisper / Qwen3-ASR，mlx-audio）。

协议
----
  启动   python3 lingolens_stt.py --model <dir> [--language zh] [--hotwords a,b]
  输入   stdin 上持续写入 **16 kHz 单声道 int16 小端 PCM**（纯流，无分帧）
  输出   stdout 按行输出 JSON；stderr 只放日志，避免污染协议
  结束   stdin EOF → 转写掉最后一段后退出

输出事件
--------
  {"type":"ready"}
  {"type":"final","text":str,"start":float,"end":float,"elapsed":float}
  {"type":"error","message":str}

为什么自己断句：Whisper 是长上下文模型，整段一次解码质量最好、也最快
（实测 33 秒音频约 0.9 秒），但它不提供实时边界；因此用能量检测切句，
只在句子结束后解码一次，延迟约「静音判定 + 解码」。
"""
import argparse
import json
import os
import queue
import re
import sys
import threading
import time

import numpy as np

SAMPLE_RATE = 16000
INT16_SCALE = 32768.0

FRAME_MS = 20
FRAME = SAMPLE_RATE * FRAME_MS // 1000

# 能量阈值。实测数据（真实会议录音）：
#   对方（系统音频）真实说话 RMS 0.05–0.2，静音处 0.000；
#   麦克风只有环境噪声时 p50=0.0056、p90=0.0083、最大 0.0277。
# 原来用 0.008 会把麦克风噪声全当成语音，切出大量近乎静音的段，
# Whisper 在这些段上会稳定产生「请不吝点赞 订阅 转发…」这类幻觉。
SILENCE_RMS = 0.012
# 自适应噪声底：取最近 3 秒的第 20 百分位当作底噪，语音阈值取其倍数。
NOISE_WINDOW_FRAMES = 150
NOISE_PERCENTILE = 20
NOISE_MULTIPLIER = 2.2
# 句子太短容易是噪声碎片。
MIN_SPEECH_SEC = 0.6
# 句尾连续静音达到该时长即断句。
SILENCE_HANG_SEC = 0.42
# 超过这个时长就找一个「安静点」断句，避免字幕迟迟不出。
SOFT_MAX_SEGMENT_SEC = 9.0
# 硬上限，不能超过 Whisper 的 30 秒窗口。
MAX_SEGMENT_SEC = 25.0
# 软断句的安静点门槛：低于它说明正处在词间停顿，此刻切句不会切断字词。
SOFT_CUT_RMS = SILENCE_RMS * 3
# 已知的 Whisper 幻觉片段：几乎只在静音/噪声上出现，命中就整段丢弃。
HALLUCINATION_MARKERS = (
    "请不吝点赞",
    "订阅转发",
    "字幕志愿者",
    "明镜与点点",
    "打赏支持",
    "字幕由",
)
# 句首回补，避免吞掉第一个字的起音。
PREROLL_FRAMES = SAMPLE_RATE * 25 // 100

# Qwen3-ASR 的语言参数用语言名（Chinese/English），不认 zh/en 代码；
# 传 None 时模型自动检测语种，中英混说更稳。
QWEN3_LANGUAGES = {
    "zh": "Chinese",
    "zh-hans": "Chinese",
    "zh-cn": "Chinese",
    "zh-hant": "Chinese",
    "yue": "Cantonese",
    "en": "English",
    "ja": "Japanese",
    "ko": "Korean",
}


def detect_model_type(model_dir):
    """读 config.json 区分模型类型；读不到就按 Whisper 处理（兼容旧模型目录）。"""
    try:
        with open(os.path.join(model_dir, "config.json"), encoding="utf-8") as fh:
            return json.load(fh).get("model_type", "whisper")
    except (OSError, ValueError):
        return "whisper"


def is_hotword_recitation(text, hotwords):
    """Qwen3-ASR 这类上下文偏置模型在噪声/音乐段上会把热词表原样背出来。
    去掉全部热词与标点后什么都不剩，就判定为背诵，整段丢弃。"""
    if not hotwords:
        return False
    remaining = text.lower()
    for word in sorted(hotwords, key=len, reverse=True):
        remaining = remaining.replace(word.lower(), "")
    remaining = re.sub(r"[\s,，.。、:：;；!！?？\-—]+", "", remaining)
    return not remaining


def is_prompt_echo(text, prompt):
    """噪声段上模型可能把提示词本身当成转写结果吐出来（Whisper 的
    initial_prompt、Qwen3-ASR 的 system_prompt 都有这毛病）。
    输出与提示高度重合就整段丢弃。"""
    if not prompt:
        return False
    strip = r"[\s,，.。、:：;；!！?？\-—]+"
    t = re.sub(strip, "", text).lower()
    p = re.sub(strip, "", prompt).lower()
    if not t or not p:
        return False
    # 整段提示被原样吐出（可能夹几个语气词）。
    if p in t:
        return True
    # 输出是提示的片段：至少 5 个字才算，避免误伤「普通话」这类正常短词。
    if len(t) >= 5 and t in p:
        return True
    # 输出 80% 以上的字符按顺序来自提示，视为回声（容忍少量改写）。
    if len(t) >= 8:
        prev = [0] * (len(p) + 1)
        for ca in t:
            cur = [0]
            for j, cb in enumerate(p, 1):
                cur.append(prev[j - 1] + 1 if ca == cb else max(prev[j], cur[j - 1]))
            prev = cur
        if prev[-1] / len(t) >= 0.8:
            return True
    return False


def emit(payload):
    sys.stdout.write(json.dumps(payload, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def log(message):
    sys.stderr.write("[stt] " + message + "\n")
    sys.stderr.flush()


class Segmenter:
    """按能量把连续 PCM 切成句子。"""

    def __init__(self):
        self._buffer = np.zeros(0, dtype=np.float32)
        self._preroll = []
        self._pending = []
        self._in_speech = False
        self._silence_run = 0.0
        self._segment_start = 0.0
        self._position = 0.0
        # 最近若干帧的 RMS，用来估底噪。
        self._recent = []

    def _threshold(self):
        if not self._recent:
            return SILENCE_RMS
        floor = float(np.percentile(self._recent, NOISE_PERCENTILE))
        return max(SILENCE_RMS, floor * NOISE_MULTIPLIER)

    def feed(self, samples):
        """喂入 float32 样本，返回已完整的 [(start, end, audio)]。"""
        if len(samples):
            self._buffer = np.concatenate([self._buffer, samples])
        completed = []

        while len(self._buffer) >= FRAME:
            frame = self._buffer[:FRAME]
            self._buffer = self._buffer[FRAME:]
            frame_start = self._position
            self._position += FRAME_MS / 1000.0
            rms = float(np.sqrt(np.mean(frame * frame)) + 1e-12)

            self._recent.append(rms)
            if len(self._recent) > NOISE_WINDOW_FRAMES:
                self._recent.pop(0)
            threshold = self._threshold()

            if rms >= threshold:
                if not self._in_speech:
                    self._in_speech = True
                    preroll = len(self._preroll)
                    self._segment_start = max(0.0, frame_start - preroll * FRAME_MS / 1000.0)
                    self._pending = list(self._preroll)
                    self._preroll = []
                self._pending.append(frame)
                self._silence_run = 0.0
                elapsed = self._position - self._segment_start
                # 到点后优先在词间停顿处切：硬切会把字词劈开，Whisper 会认错甚至转成繁体。
                if elapsed >= MAX_SEGMENT_SEC or (
                    elapsed >= SOFT_MAX_SEGMENT_SEC and rms < SOFT_CUT_RMS
                ):
                    completed.append(self._cut())
            else:
                if self._in_speech:
                    self._pending.append(frame)
                    self._silence_run += FRAME_MS / 1000.0
                    if self._silence_run >= SILENCE_HANG_SEC:
                        completed.append(self._cut())
                else:
                    self._preroll.append(frame)
                    if len(self._preroll) > PREROLL_FRAMES:
                        self._preroll.pop(0)

        return completed

    def flush(self):
        if self._in_speech:
            return [self._cut()]
        return []

    def _cut(self):
        audio = np.concatenate(self._pending) if self._pending else np.zeros(0, dtype=np.float32)
        start, end = self._segment_start, self._position
        # 记下这一段的平均能量，供转写阶段做二次过滤。
        self._last_rms = float(np.sqrt(np.mean(audio * audio))) if len(audio) else 0.0
        self._in_speech = False
        self._pending = []
        self._silence_run = 0.0
        # 不要拿本句尾部做回补：那段音频已经转写过了，再喂一次会得到重复文字。
        # 起音回补只靠随后的静音帧自然累积。
        self._preroll = []
        return (start, end, audio)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--language", default="zh")
    parser.add_argument("--hotwords", default="")
    parser.add_argument("--prompt", default="")
    args = parser.parse_args()

    hotwords = [word.strip() for word in args.hotwords.split(",") if word.strip()]
    model_type = detect_model_type(args.model)
    # 默认简体提示只给 Whisper：它偶尔输出繁体，需要 prompt 压住。
    # Qwen3-ASR 默认就输出简体，系统提示反而容易在噪声段被原样吐出来。
    prompt = args.prompt
    if not prompt and model_type != "qwen3_asr" and args.language in ("zh", "zh-Hans", "zh-CN"):
        prompt = "以下是普通话会议记录，请用简体中文转写。"

    language = args.language
    if model_type == "qwen3_asr":
        language = QWEN3_LANGUAGES.get(args.language.lower())
        if args.language.lower() in ("auto", ""):
            language = None

    from mlx_audio.stt import load

    started = time.time()
    model = load(args.model)
    log("model loaded in %.2fs type=%s hotwords=%d" % (time.time() - started, model_type, len(hotwords)))
    emit({"type": "ready"})

    segments = queue.Queue()

    def worker():
        while True:
            item = segments.get()
            if item is None:
                return
            start, end, audio = item
            if len(audio) / SAMPLE_RATE < MIN_SPEECH_SEC:
                log("丢弃过短片段 %.2fs" % (len(audio) / SAMPLE_RATE))
                continue
            # 整段平均能量太低：几乎一定是噪声，别送去诱骗 Whisper。
            seg_rms = float(np.sqrt(np.mean(audio * audio))) if len(audio) else 0.0
            if seg_rms < SILENCE_RMS:
                log("丢弃低能量片段 rms=%.4f 时长=%.2fs" % (seg_rms, len(audio) / SAMPLE_RATE))
                continue
            began = time.time()
            try:
                if model_type == "qwen3_asr":
                    # Qwen3-ASR 没有 initial_prompt：提示走 system_prompt，
                    # 热词由 mlx-audio 内部并入系统提示。
                    result = model.generate(
                        audio,
                        language=language,
                        hotwords=hotwords or None,
                        system_prompt=prompt or None,
                    )
                else:
                    result = model.generate(
                        audio,
                        language=args.language,
                        hotwords=hotwords or None,
                        initial_prompt=prompt or None,
                    )
                text = (result.text or "").strip()
            except Exception as exc:  # 单句失败不应终止整个会话
                emit({"type": "error", "message": "%s: %s" % (type(exc).__name__, exc)})
                continue
            if text and any(marker in text for marker in HALLUCINATION_MARKERS):
                log("丢弃幻觉片段: %s" % text[:30])
                continue
            if text and is_hotword_recitation(text, hotwords):
                log("丢弃热词背诵片段: %s" % text[:40])
                continue
            if text and is_prompt_echo(text, prompt):
                log("丢弃提示回声片段: %s" % text[:40])
                continue
            if text:
                emit({
                    "type": "final",
                    "text": text,
                    "start": round(start, 3),
                    "end": round(end, 3),
                    "elapsed": round(time.time() - began, 3),
                })

    thread = threading.Thread(target=worker, daemon=True)
    thread.start()

    segmenter = Segmenter()
    stdin = sys.stdin.buffer
    remainder = b""
    while True:
        try:
            chunk = stdin.read(1 << 16)
        except KeyboardInterrupt:
            break
        if not chunk:
            break
        chunk = remainder + chunk
        usable = len(chunk) - (len(chunk) % 2)
        remainder = chunk[usable:]
        if not usable:
            continue
        samples = np.frombuffer(chunk[:usable], dtype="<i2").astype(np.float32) / INT16_SCALE
        for segment in segmenter.feed(samples):
            segments.put(segment)

    for segment in segmenter.flush():
        segments.put(segment)
    segments.put(None)
    thread.join(timeout=180)
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
