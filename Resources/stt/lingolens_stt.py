#!/usr/bin/env python3
"""LingoLens 本地语音转写边车（Whisper / mlx-audio）。

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
import queue
import sys
import threading
import time

import numpy as np

SAMPLE_RATE = 16000
INT16_SCALE = 32768.0

FRAME_MS = 20
FRAME = SAMPLE_RATE * FRAME_MS // 1000

# 能量阈值：实测普通话近场说话 RMS 约 0.02–0.15，环境噪声常在 0.005 以下。
SILENCE_RMS = 0.008
# 句尾连续静音达到该时长即断句。
SILENCE_HANG_SEC = 0.42
# 超过这个时长就找一个「安静点」断句，避免字幕迟迟不出。
SOFT_MAX_SEGMENT_SEC = 9.0
# 硬上限，不能超过 Whisper 的 30 秒窗口。
MAX_SEGMENT_SEC = 25.0
# 软断句的安静点门槛：低于它说明正处在词间停顿，此刻切句不会切断字词。
SOFT_CUT_RMS = SILENCE_RMS * 3
# 过短的段丢弃（咳嗽、敲键盘）。
MIN_SPEECH_SEC = 0.25
# 句首回补，避免吞掉第一个字的起音。
PREROLL_FRAMES = SAMPLE_RATE * 25 // 100


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

            if rms >= SILENCE_RMS:
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
    # 中文场景默认给一句简体提示：Whisper 偶尔会输出繁体，prompt 能明显压住。
    prompt = args.prompt
    if not prompt and args.language in ("zh", "zh-Hans", "zh-CN"):
        prompt = "以下是普通话会议记录，请用简体中文转写。"

    from mlx_audio.stt import load

    started = time.time()
    model = load(args.model)
    log("model loaded in %.2fs hotwords=%d" % (time.time() - started, len(hotwords)))
    emit({"type": "ready"})

    segments = queue.Queue()

    def worker():
        while True:
            item = segments.get()
            if item is None:
                return
            start, end, audio = item
            if len(audio) / SAMPLE_RATE < MIN_SPEECH_SEC:
                continue
            began = time.time()
            try:
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
